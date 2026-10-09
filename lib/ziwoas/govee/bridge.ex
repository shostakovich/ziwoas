defmodule Ziwoas.Govee.Bridge do
  @moduledoc false
  use GenServer

  require Logger

  alias Ziwoas.Govee.{CommandRouter, DeviceRegistry, Lan, PlatformApi, States}
  alias Ziwoas.Lights

  @listen_backoff_min_ms 1_000
  @listen_backoff_max_ms 60_000
  @state_fields [:on, :reachable, :brightness, :color, :color_temp_k, :zone_states]
  @command_timeout_ms Application.compile_env(:ziwoas, :govee_command_timeout_ms, 5_000)
  @silent_after_polls 3
  @watch_poll_ms 2_000

  @type verb ::
          {:power, boolean}
          | {:brightness, 1..100}
          | {:color, %{r: 0..255, g: 0..255, b: 0..255}}
          | {:color_temp, pos_integer}
          | {:zone, String.t(), boolean}
          | {:scene, String.t()}

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @spec command(String.t(), verb, GenServer.server()) :: :ok | {:error, term}
  def command(key, verb, server \\ __MODULE__) do
    case GenServer.whereis(server) do
      nil -> {:error, :unavailable}
      pid -> GenServer.call(pid, {:command, key, verb}, @command_timeout_ms)
    end
  catch
    :exit, reason ->
      Logger.warning("Govee bridge: #{inspect(verb)} for #{key}: #{inspect(reason)}")
      {:error, :unavailable}
  end

  @doc "Only a lamp once heard on the LAN can fall silent; without a bridge none is."
  @spec silent?(String.t(), GenServer.server()) :: boolean
  def silent?(key, server \\ __MODULE__) do
    case call(server, {:silent?, key}) do
      {:error, :unavailable} -> false
      silent -> silent
    end
  end

  @doc "The watcher gets `{:lamp_heard, key, telemetry | nil}` for every LAN reply of the lamp."
  @spec watch(String.t(), GenServer.server(), pid) :: :ok | {:error, :unavailable}
  def watch(key, server \\ __MODULE__, watcher \\ self()),
    do: call(server, {:watch, key, watcher})

  @spec unwatch(String.t(), GenServer.server()) :: :ok
  def unwatch(key, server \\ __MODULE__) do
    call(server, {:unwatch, key})
    :ok
  end

  defp call(server, request) do
    case GenServer.whereis(server) do
      nil -> {:error, :unavailable}
      pid -> GenServer.call(pid, request, @command_timeout_ms)
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(opts) do
    govee = Keyword.fetch!(opts, :govee)

    state = %{
      govee: govee,
      api: PlatformApi.new(govee.api_key, Keyword.get(opts, :api_req, [])),
      registry:
        DeviceRegistry.new(Map.new(govee.names, fn {mac, %{name: name}} -> {mac, name} end)),
      store: States.new(govee.pending_window_seconds * 1.0),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) / 1000 end),
      send: Keyword.get(opts, :send, &Lan.send_datagram/1),
      put_lamp: Keyword.get(opts, :put_lamp, &Lights.put_lamp/1),
      put_state: Keyword.get(opts, :put_state, &Lights.put_state/2),
      tasks: Keyword.get(opts, :tasks, Ziwoas.Govee.Tasks),
      pending: %{},
      heard_at: %{},
      watchers: %{},
      watch_poll_ms: Keyword.get(opts, :watch_poll_ms, @watch_poll_ms),
      watch_polling: false,
      socket: nil,
      listen_port: Keyword.get(opts, :listen_port, Lan.listen_port()),
      listen_backoff_ms: @listen_backoff_min_ms,
      bootstrapped: false
    }

    send(self(), :bootstrap)
    send(self(), :lan_poll)
    Process.send_after(self(), :api_poll, govee.api_poll_seconds * 1000)
    Logger.info("Govee bridge: starting")
    {:ok, listen(state)}
  end

  def listen_port(server \\ __MODULE__), do: GenServer.call(server, :listen_port)

  @impl true
  def handle_call(:listen_port, _from, %{socket: nil} = state), do: {:reply, nil, state}

  def handle_call(:listen_port, _from, state),
    do: {:reply, elem(:inet.port(state.socket), 1), state}

  def handle_call({:command, key, verb}, _from, state) do
    {reply, state} = run_command(state, key, verb)
    {:reply, reply, state}
  end

  def handle_call({:silent?, key}, _from, state) do
    silent_after = @silent_after_polls * state.govee.lan_poll_seconds

    silent =
      case state.heard_at[key] do
        nil -> false
        heard_at -> state.clock.() - heard_at > silent_after
      end

    {:reply, silent, state}
  end

  def handle_call({:watch, key, watcher}, _from, state) do
    state = drop_watcher(state, key)
    ref = Process.monitor(watcher)
    state = %{state | watchers: Map.put(state.watchers, key, {watcher, ref})}
    {:reply, :ok, start_watch_poll(state)}
  end

  def handle_call({:unwatch, key}, _from, state), do: {:reply, :ok, drop_watcher(state, key)}

  @impl true
  def handle_info(:bootstrap, state),
    do: {:noreply, async(state, :refreshed, fn -> refresh(state) end)}

  def handle_info(:lan_poll, state) do
    lan(state, :discover)

    for device <- DeviceRegistry.all(state.registry),
        device.ip,
        do: lan(state, {:request_status, device.ip})

    Process.send_after(self(), :lan_poll, state.govee.lan_poll_seconds * 1000)
    {:noreply, state}
  end

  # Re-armed before the task starts: however the task ends, the next poll comes.
  def handle_info(:api_poll, state) do
    Process.send_after(self(), :api_poll, state.govee.api_poll_seconds * 1000)
    devices = DeviceRegistry.all(state.registry)
    api = state.api

    {:noreply,
     async(state, :api_states, fn ->
       {:ok, Enum.map(devices, &{&1, PlatformApi.state(api, &1.sku, &1.api_id)})}
     end)}
  end

  def handle_info({ref, result}, state) when is_map_key(state.pending, ref) do
    Process.demonitor(ref, [:flush])
    {tag, pending} = Map.pop(state.pending, ref)
    {:noreply, finished(%{state | pending: pending}, tag, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.pending, ref) do
    {tag, pending} = Map.pop(state.pending, ref)
    {:noreply, finished(%{state | pending: pending}, tag, {:error, {:exit, reason}})}
  end

  def handle_info(:watch_poll, state) when state.watchers == %{},
    do: {:noreply, %{state | watch_polling: false}}

  def handle_info(:watch_poll, state) do
    lan(state, :discover)

    for key <- Map.keys(state.watchers),
        device = DeviceRegistry.find(state.registry, key),
        device && device.ip,
        do: lan(state, {:request_status, device.ip})

    Process.send_after(self(), :watch_poll, state.watch_poll_ms)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    watchers = Map.reject(state.watchers, fn {_key, {_watcher, watch}} -> watch == ref end)
    {:noreply, %{state | watchers: watchers}}
  end

  def handle_info(:listen, %{socket: nil} = state), do: {:noreply, listen(state)}

  def handle_info({:udp, socket, ip, _port, payload}, %{socket: socket} = state),
    do: {:noreply, handle_datagram(state, payload, ip |> :inet.ntoa() |> List.to_string())}

  def handle_info(message, state) do
    Logger.debug("Govee bridge: ignoring #{inspect(message)}")
    {:noreply, state}
  end

  defp finished(state, :refreshed, result) do
    state = adopt_refresh(state, result)
    if state.bootstrapped, do: state, else: bootstrap(state)
  end

  defp finished(state, :api_states, {:ok, results}),
    do: Enum.reduce(results, state, &apply_api(&2, &1, true))

  defp finished(state, :api_states, {:error, reason}) do
    Logger.warning("Govee bridge: API poll failed: #{inspect(reason)}")
    state
  end

  defp finished(state, {:clarified, device}, result),
    do: apply_api(state, {device, result}, false)

  defp finished(state, {:controlled, key, verb}, {:ok, _}), do: record(state, key, verb)

  defp finished(state, {:controlled, key, verb}, {:error, reason}) do
    Logger.warning("Govee bridge: #{inspect(verb)} for #{key} failed: #{inspect(reason)}")
    state
  end

  defp refresh(state) do
    scenes = fn raw ->
      PlatformApi.scenes(state.api, to_string(raw["sku"]), to_string(raw["device"]))
    end

    with {:ok, raw} <- PlatformApi.devices(state.api),
         do: {:ok, DeviceRegistry.refresh(state.registry, raw, scenes)}
  end

  # IPs found while the refresh ran win over the snapshot it started from.
  defp adopt_refresh(state, {:ok, registry}) do
    registry =
      Enum.reduce(DeviceRegistry.all(state.registry), registry, fn device, acc ->
        if device.ip, do: DeviceRegistry.record_lan_ip(acc, device.key, device.ip), else: acc
      end)

    %{state | registry: registry}
  end

  defp adopt_refresh(state, {:error, reason}) do
    Logger.warning("Govee.DeviceRegistry: refresh failed: #{inspect(reason)}")
    state
  end

  defp bootstrap(state) do
    case DeviceRegistry.all(state.registry) do
      [] ->
        Logger.warning(
          "Govee bridge: no devices after refresh; retrying in #{state.govee.api_poll_seconds}s"
        )

        Process.send_after(self(), :bootstrap, state.govee.api_poll_seconds * 1000)
        state

      devices ->
        lan(state, :discover)
        Enum.each(devices, &announce_device(state, &1))
        Logger.info("Govee bridge: bootstrapped #{length(devices)} devices")
        %{state | bootstrapped: true}
    end
  end

  defp announce_device(state, device) do
    if device.ip, do: lan(state, {:request_status, device.ip})

    lamp =
      Map.take(device, [
        :key,
        :name,
        :sku,
        :supports_color,
        :supports_color_temp,
        :color_temp_min_k,
        :color_temp_max_k,
        :zones,
        :scenes
      ])

    with {:error, reason} <- state.put_lamp.(lamp),
         do: Logger.warning("Govee bridge: lamp #{device.key} refused: #{inspect(reason)}")
  end

  defp listen(%{listen_port: false} = state), do: state

  # A port still held by a bridge not yet gone is retried with backoff.
  defp listen(%{listen_port: port} = state) do
    opts = [
      :binary,
      active: true,
      reuseaddr: true,
      reuseport: true,
      ip: {0, 0, 0, 0},
      add_membership: {Lan.scan_group(), {0, 0, 0, 0}}
    ]

    case :gen_udp.open(port, opts) do
      {:ok, socket} ->
        %{state | socket: socket, listen_backoff_ms: @listen_backoff_min_ms}

      {:error, reason} ->
        Logger.error(
          "Govee bridge listener: #{inspect(reason)}; retrying in #{state.listen_backoff_ms} ms"
        )

        Process.send_after(self(), :listen, state.listen_backoff_ms)

        %{
          state
          | listen_backoff_ms: min(state.listen_backoff_ms * 2, @listen_backoff_max_ms)
        }
    end
  end

  defp handle_datagram(state, payload, sender_ip) do
    cond do
      scan = Lan.parse_scan(payload) ->
        state = %{
          state
          | registry: DeviceRegistry.record_lan_ip(state.registry, scan.mac, scan.ip)
        }

        case DeviceRegistry.find(state.registry, DeviceRegistry.normalize_mac(scan.mac)) do
          nil -> state
          device -> heard(state, device.key, nil)
        end

      status = Lan.parse_status(payload) ->
        case DeviceRegistry.find_by_ip(state.registry, sender_ip) do
          nil -> state
          device -> apply_lan(state, device, Lan.telemetry(status))
        end

      true ->
        state
    end
  end

  defp heard(state, key, telemetry) do
    case state.watchers[key] do
      {watcher, _ref} -> send(watcher, {:lamp_heard, key, telemetry})
      nil -> :ok
    end

    %{state | heard_at: Map.put(state.heard_at, key, state.clock.())}
  end

  defp start_watch_poll(%{watch_polling: true} = state), do: state

  defp start_watch_poll(state) do
    send(self(), :watch_poll)
    %{state | watch_polling: true}
  end

  defp drop_watcher(state, key) do
    case Map.pop(state.watchers, key) do
      {nil, _watchers} ->
        state

      {{_watcher, ref}, watchers} ->
        Process.demonitor(ref, [:flush])
        %{state | watchers: watchers}
    end
  end

  defp apply_lan(state, device, telemetry) do
    state = heard(state, device.key, telemetry)

    {result, store} =
      States.apply_telemetry(state.store, device.key, telemetry, :lan, state.clock.())

    state = %{state | store: store}
    if result.changed, do: report_state(state, device.key, result.published)

    if result.needs_api_clarification do
      api = state.api

      async(state, {:clarified, device}, fn ->
        PlatformApi.state(api, device.sku, device.api_id)
      end)
    else
      state
    end
  end

  defp apply_api(state, {device, {:ok, map}}, report?) do
    case PlatformApi.telemetry(map, device.zones) do
      {:ok, telemetry} ->
        {result, store} =
          States.apply_telemetry(state.store, device.key, telemetry, :api, state.clock.())

        if report? and result.changed, do: report_state(state, device.key, result.published)
        %{state | store: store}

      :error ->
        Logger.warning("Govee.Reconciler: API state of #{device.key} does not coerce")
        state
    end
  end

  defp apply_api(state, {device, {:error, reason}}, _report?) do
    Logger.warning("Govee.Reconciler: api state #{device.key}: #{inspect(reason)}")
    state
  end

  defp run_command(state, key, verb) do
    with %{} = device <- DeviceRegistry.find(state.registry, key) || {:error, :unknown_lamp},
         {:ok, route} <- CommandRouter.route(device, verb) do
      dispatch(state, key, verb, route)
    else
      {:error, reason} = error ->
        Logger.warning("Govee bridge: #{inspect(verb)} for #{key}: #{inspect(reason)}")
        {error, state}
    end
  end

  defp dispatch(state, key, verb, {:lan, commands}) do
    sent =
      Enum.reduce_while(commands, :ok, fn command, :ok ->
        case lan(state, command) do
          {:error, reason} -> {:halt, {:error, {:lan, reason}}}
          _sent -> {:cont, :ok}
        end
      end)

    case sent do
      :ok -> {:ok, record(state, key, verb)}
      error -> {error, state}
    end
  end

  defp dispatch(state, key, verb, {:api, control}) do
    api = state.api
    {:ok, async(state, {:controlled, key, verb}, fn -> PlatformApi.control(api, control) end)}
  end

  defp record(state, key, verb) do
    changes = CommandRouter.changes(verb, States.published(state.store, key))
    {published, store} = States.record_command(state.store, key, changes, state.clock.())
    report_state(state, key, published)
    %{state | store: store}
  end

  defp lan(state, command), do: state.send.(Lan.datagram(command))

  defp report_state(state, key, published) do
    lamp_state =
      for {field, value} <- Map.take(published, @state_fields),
          not is_nil(value),
          into: %{on: false, reachable: true},
          do: {field, value}

    with {:error, reason} <- state.put_state.(key, lamp_state),
         do: Logger.error("Govee bridge: state of #{key} not stored: #{inspect(reason)}")
  end

  defp async(state, tag, fun) do
    task = Task.Supervisor.async_nolink(state.tasks, fun)
    %{state | pending: Map.put(state.pending, task.ref, tag)}
  end
end
