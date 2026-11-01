defmodule Ziwoas.Hue.Bridge do
  @moduledoc false
  use GenServer

  require Logger

  alias Ziwoas.Hue.{Client, Events, Light, Resources}
  alias Ziwoas.Lights

  @behaviour Ziwoas.Lights.Bridge

  @retry_min_ms 1_000
  @retry_max_ms 60_000
  @stable_ms 60_000
  @idle_ms :timer.minutes(10)
  @buffer_max_bytes 1_048_576
  @call_timeout_ms 5_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl Ziwoas.Lights.Bridge
  @spec command(String.t(), Lights.Bridge.verb(), GenServer.server()) :: :ok | {:error, term}
  def command(key, verb, server \\ __MODULE__) do
    with {:ok, client, id, body} <- call(server, {:update, key, verb}),
         :ok <- Client.update_light(client, id, body) do
      :ok
    else
      {:error, reason} = error ->
        Logger.warning("Hue bridge: #{inspect(verb)} for #{key}: #{inspect(reason)}")
        error
    end
  end

  @doc "Silent while the bridge reports the lamp's Zigbee connection not connected."
  @impl Ziwoas.Lights.Bridge
  @spec silent?(String.t(), GenServer.server()) :: boolean
  def silent?(key, server \\ __MODULE__), do: call(server, {:silent?, key}) == true

  @doc "The watcher gets `{:lamp_heard, key, state}` for every event that finds the lamp connected."
  @impl Ziwoas.Lights.Bridge
  @spec watch(String.t(), GenServer.server(), pid) :: :ok | {:error, :unavailable}
  def watch(key, server \\ __MODULE__, watcher \\ self()),
    do: call(server, {:watch, key, watcher})

  @impl Ziwoas.Lights.Bridge
  @spec unwatch(String.t(), GenServer.server()) :: :ok
  def unwatch(key, server \\ __MODULE__) do
    call(server, {:unwatch, key})
    :ok
  end

  defp call(server, request), do: Lights.Bridge.call(server, request, @call_timeout_ms)

  @impl true
  def init(opts) do
    hue = Keyword.fetch!(opts, :hue)
    retry_min_ms = Keyword.get(opts, :retry_ms, @retry_min_ms)

    state = %{
      client: Client.new(hue.host, hue.application_key, Keyword.get(opts, :req, [])),
      put_lamp: Keyword.get(opts, :put_lamp, &Lights.put_lamp/1),
      put_state: Keyword.get(opts, :put_state, &Lights.put_state/2),
      stored_keys: Keyword.get(opts, :stored_keys, fn -> Lights.keys(:hue) end),
      resources: %{},
      watchers: %{},
      stream: nil,
      buffer: "",
      opened_at: nil,
      idle_ms: Keyword.get(opts, :idle_ms, @idle_ms),
      idle_timer: nil,
      retry_min_ms: retry_min_ms,
      retry_max_ms: Keyword.get(opts, :retry_max_ms, @retry_max_ms),
      retry_ms: retry_min_ms,
      stable_ms: Keyword.get(opts, :stable_ms, @stable_ms)
    }

    send(self(), :connect)
    Logger.info("Hue bridge: starting")
    {:ok, state}
  end

  @impl true
  def handle_call({:update, key, verb}, _from, state) do
    reply =
      with %{} = light <- state.resources[Light.id(key)] || {:error, :unknown_lamp},
           {:ok, body} <- Light.update(light, verb),
           do: {:ok, state.client, light["id"], body}

    {:reply, reply, state}
  end

  def handle_call({:silent?, key}, _from, state) do
    id = Light.id(key)
    silent = Map.has_key?(state.resources, id) and not Resources.reachable?(state.resources, id)
    {:reply, silent, state}
  end

  def handle_call({:watch, key, watcher}, _from, state),
    do:
      {:reply, :ok, %{state | watchers: Lights.Bridge.add_watcher(state.watchers, key, watcher)}}

  def handle_call({:unwatch, key}, _from, state),
    do: {:reply, :ok, %{state | watchers: Lights.Bridge.drop_watcher(state.watchers, key)}}

  @impl true
  def handle_info(:connect, state) do
    case identified(state.client) do
      {:ok, client} -> {:noreply, connect(%{state | client: client})}
      {:error, reason} -> {:noreply, connect_failed(state, reason)}
    end
  end

  def handle_info(:reload, state) do
    case Client.resources(state.client) do
      {:ok, resources} ->
        {:noreply, load(state, resources)}

      {:error, reason} ->
        Logger.warning("Hue bridge: reload failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info({:stream_idle, token}, %{idle_timer: {_timer, token}} = state),
    do: {:noreply, dropped(state, :idle)}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state),
    do: {:noreply, %{state | watchers: Lights.Bridge.watcher_down(state.watchers, ref)}}

  def handle_info(message, %{stream: stream} = state) when stream != nil do
    case Req.parse_message(stream, message) do
      {:ok, parts} -> {:noreply, Enum.reduce(parts, state, &stream_part/2)}
      {:error, reason} -> {:noreply, dropped(state, reason)}
      :unknown -> ignore(message, state)
    end
  end

  def handle_info(message, state), do: ignore(message, state)

  defp ignore(message, state) do
    Logger.debug("Hue bridge: ignoring #{inspect(message)}")
    {:noreply, state}
  end

  # Once learned, the bridge ID is kept: a reconnect only takes a bridge with that ID.
  defp identified(%Client{bridge_id: nil} = client), do: Client.identify(client)
  defp identified(client), do: {:ok, client}

  defp connect(state) do
    case open(state.client) do
      {:ok, stream, resources} ->
        Logger.info("Hue bridge: connected to #{state.client.bridge_id}")

        %{state | stream: stream, buffer: "", opened_at: now()}
        |> rearm_idle()
        |> load(resources)

      {:error, reason} ->
        connect_failed(state, reason)
    end
  end

  # The stream opens before the full read, so no change falls between the two.
  defp open(client) do
    with {:ok, stream} <- Client.open_events(client) do
      case Client.resources(client) do
        {:ok, resources} ->
          {:ok, stream, resources}

        error ->
          Req.cancel_async_response(stream)
          error
      end
    end
  end

  defp connect_failed(state, reason) do
    Logger.warning("Hue bridge: connect failed: #{inspect(reason)}")
    retry(state)
  end

  defp load(state, resources) do
    state = %{state | resources: Resources.index(resources)}

    for lamp <- Resources.lamps(state.resources),
        {:error, reason} <- [state.put_lamp.(lamp)],
        do: Logger.warning("Hue bridge: lamp #{lamp.key} refused: #{inspect(reason)}")

    light_ids = Resources.light_ids(state.resources)
    publish(state, light_ids)
    unreach_removed(state, MapSet.new(light_ids, &Light.key/1))
    state
  end

  defp unreach_removed(state, present) do
    for key <- state.stored_keys.(),
        not MapSet.member?(present, key),
        {:error, reason} <- [state.put_state.(key, %{on: false, reachable: false})],
        do: Logger.error("Hue bridge: state of #{key} not stored: #{inspect(reason)}")
  end

  defp stream_part(_part, %{stream: nil} = state), do: state

  defp stream_part({:data, chunk}, state) do
    {events, rest} = Events.parse(state.buffer <> chunk)
    state = Enum.reduce(events, rearm_idle(%{state | buffer: rest}), &event/2)
    if byte_size(rest) > @buffer_max_bytes, do: dropped(state, :event_too_large), else: state
  end

  defp stream_part(:done, state), do: dropped(state, :closed)
  defp stream_part(_trailers, state), do: state

  defp event(%{"type" => "update", "data" => changes}, state) when is_list(changes) do
    {resources, touched} = Resources.update(state.resources, changes)
    state = %{state | resources: resources}
    Enum.each(touched, &tell_watcher(state, &1))
    publish(state, touched)
    state
  end

  defp event(%{"type" => type, "data" => changes}, state)
       when type in ["add", "delete"] and is_list(changes) do
    if Enum.any?(changes, &Resources.kept?/1), do: send(self(), :reload)
    state
  end

  defp event(_event, state), do: state

  # Only events hear a lamp: a full read reports a lamp just cut off as connected for a while.
  defp tell_watcher(state, id) do
    key = Light.key(id)

    with {watcher, _ref} <- state.watchers[key],
         true <- Resources.reachable?(state.resources, id),
         do: send(watcher, {:lamp_heard, key, Resources.state(state.resources, id)})
  end

  # Every time, not only on a change: lamp commands write the same row.
  defp publish(state, light_ids) do
    for id <- light_ids,
        key = Light.key(id),
        {:error, reason} <- [state.put_state.(key, Resources.state(state.resources, id))],
        do: Logger.error("Hue bridge: state of #{key} not stored: #{inspect(reason)}")
  end

  defp dropped(state, reason) do
    level = if reason == :idle, do: :info, else: :warning
    Logger.log(level, "Hue bridge: event stream ended: #{inspect(reason)}")
    if state.stream, do: Req.cancel_async_response(state.stream)
    cancel_idle(state)
    stable = state.opened_at && now() - state.opened_at >= state.stable_ms
    retry_ms = if stable, do: state.retry_min_ms, else: state.retry_ms

    retry(%{state | stream: nil, buffer: "", opened_at: nil, idle_timer: nil, retry_ms: retry_ms})
  end

  defp retry(state) do
    Process.send_after(self(), :connect, state.retry_ms)
    %{state | retry_ms: min(state.retry_ms * 2, state.retry_max_ms)}
  end

  defp rearm_idle(state) do
    cancel_idle(state)
    token = make_ref()
    timer = Process.send_after(self(), {:stream_idle, token}, state.idle_ms)
    %{state | idle_timer: {timer, token}}
  end

  defp cancel_idle(%{idle_timer: {timer, _token}}), do: Process.cancel_timer(timer)
  defp cancel_idle(_state), do: :ok

  defp now, do: System.monotonic_time(:millisecond)
end
