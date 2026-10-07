defmodule Ziwoas.Govee.Bridge do
  @moduledoc """
  The lamps' side of `Ziwoas.Lights`. One process holds the device registry and
  the state store; every Platform API call runs in a task under
  `Ziwoas.Govee.Tasks` (`Task.Supervisor.async_nolink/2`), so a slow or
  rate-limited cloud never stalls the LAN path.

    * **Bootstrap** — load the lamps from the Platform API, hand each one to
      `Lights.put_lamp/1`, discover the LAN; retried every `api_poll_seconds`
      until some lamp is known.
    * **LAN** — listen on UDP 4002 (multicast group joined) for scan and
      `devStatus` replies; every `lan_poll_seconds` re-discover and ask each lamp
      with an IP for its status. A reading that changes the lamp's state goes to
      `Lights.put_state/2`; a deviating one asks the API.
    * **API** — every `api_poll_seconds` the cloud state of each lamp, adopted as
      the truth.
    * **Commands** — `command/3` (from `Ziwoas.Lights`) goes over the LAN at once
      or through the API in a task (`Ziwoas.Govee.CommandRouter`); the optimistic
      state is recorded once the command went out.
  """
  use GenServer

  require Logger

  alias Ziwoas.Govee.{CommandRouter, DeviceRegistry, Lan, PlatformApi, States}
  alias Ziwoas.Lights

  @listen_backoff_min_ms 1_000
  @listen_backoff_max_ms 60_000
  @state_fields [:on, :reachable, :brightness, :color, :color_temp_k, :zone_states]
  @command_timeout_ms Application.compile_env(:ziwoas, :govee_command_timeout_ms, 5_000)

  @type verb ::
          {:power, boolean}
          | {:brightness, 1..100}
          | {:color, %{r: 0..255, g: 0..255, b: 0..255}}
          | {:color_temp, pos_integer}
          | {:zone, String.t(), boolean}
          | {:scene, String.t()}

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc """
  Sends `verb` to the lamp `key`: `:ok` once it went out over the LAN or its API
  call was started, `{:error, :unavailable}` without a running bridge or one
  that does not answer in time, `{:error, :unknown_lamp | :unknown_scene |
  {:lan, reason}}` otherwise.
  """
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

  @doc """
  Options: `:govee` (`Config.Govee`); for tests `:name`, `:api_req` (Req options),
  `:tasks` (a `Task.Supervisor`, default `Ziwoas.Govee.Tasks`), `:listen_port`
  (default 4002, `false` for none), `:send` (a datagram sender), `:put_lamp` and
  `:put_state` (default `Lights.put_lamp/1`, `Lights.put_state/2`), `:clock`
  (monotonic seconds).
  """
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

  @doc "The port the LAN listener is bound to (tests)."
  def listen_port(server \\ __MODULE__), do: GenServer.call(server, :listen_port)

  @impl true
  def handle_call(:listen_port, _from, %{socket: nil} = state), do: {:reply, nil, state}

  def handle_call(:listen_port, _from, state),
    do: {:reply, elem(:inet.port(state.socket), 1), state}

  def handle_call({:command, key, verb}, _from, state) do
    {reply, state} = run_command(state, key, verb)
    {:reply, reply, state}
  end

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

  def handle_info(:listen, %{socket: nil} = state), do: {:noreply, listen(state)}

  def handle_info({:udp, socket, ip, _port, payload}, %{socket: socket} = state),
    do: {:noreply, handle_datagram(state, payload, ip |> :inet.ntoa() |> List.to_string())}

  def handle_info(message, state) do
    Logger.debug("Govee bridge: ignoring #{inspect(message)}")
    {:noreply, state}
  end

  # --- Task results -------------------------------------------------------------

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

  # --- Bootstrap and registry ---------------------------------------------------

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

  # --- LAN ----------------------------------------------------------------------

  defp listen(%{listen_port: false} = state), do: state

  # A port another process holds (a bridge not yet gone) is retried with backoff,
  # 1 s to 60 s: without its listener the bridge hears no lamp.
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
        %{state | registry: DeviceRegistry.record_lan_ip(state.registry, scan.mac, scan.ip)}

      status = Lan.parse_status(payload) ->
        case DeviceRegistry.find_by_ip(state.registry, sender_ip) do
          nil -> state
          device -> apply_lan(state, device, status)
        end

      true ->
        state
    end
  end

  defp apply_lan(state, device, status) do
    {result, store} =
      States.apply_telemetry(
        state.store,
        device.key,
        Lan.telemetry(status),
        :lan,
        state.clock.()
      )

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

  # --- API ----------------------------------------------------------------------

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

  # --- Commands -----------------------------------------------------------------

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

  # --- Effects ------------------------------------------------------------------

  defp lan(state, command), do: state.send.(Lan.datagram(command))

  # A store entry as `Lights.put_state/2` takes it: a nil clears nothing there,
  # power defaults to off and reachability to reachable.
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
