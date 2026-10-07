defmodule Ziwoas.Govee.Bridge do
  @moduledoc """
  Rails' `Govees::Bridge` (task `govee_bridge`): the lamps' side of the
  `govees/<key>/{config,state,set}` contract. One process holds the device
  registry and the state store; the Platform API calls run in tasks so a slow or
  rate-limited cloud never stalls the LAN path.

    * **Bootstrap** — load the lamps from the Platform API, publish each one's
      config (retained), discover the LAN; retried every `api_poll_seconds` until
      some lamp is known.
    * **LAN** — listen on UDP 4002 (multicast group joined) for scan and
      `devStatus` replies; every `lan_poll_seconds` re-discover and ask each lamp
      with an IP for its status. A reading that changes the published state is
      published (retained); a deviating one asks the API.
    * **API** — every `api_poll_seconds` the cloud state of each lamp, adopted as
      the truth.
    * **Commands** — `govees/+/set` (via `Ziwoas.Govee.CommandHandler` on the
      `ziwoas-phoenix-govee` connection) go through `Ziwoas.Govee.CommandRouter`;
      the optimistic state is published at once.

  As owner it does all of that. In **shadow** mode it neither binds the LAN port
  (Rails' bridge listens there and would lose replies to a second socket) nor sends
  a datagram, consumes no command and publishes nothing; it only runs the Platform
  API reads and logs what it would publish.
  """
  use GenServer

  require Logger

  alias Ziwoas.{Mqtt, Ownership, RubyJSON}
  alias Ziwoas.Govee.{CommandRouter, DeviceRegistry, Lan, Messages, PlatformApi, StateStore}

  @task :govee_bridge
  @client_id "ziwoas-phoenix-govee"
  @listen_backoff_min_ms 1_000
  @listen_backoff_max_ms 60_000

  def client_id, do: @client_id

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc """
  Options: `:govee` (`Config.Govee`), `:owner` (default the task's mode); for tests
  `:name`, `:api_req` (Req options),
  `:listen_port` (default 4002, `false` for none), `:send` (a datagram sender),
  `:publish` (a function of topic, payload), `:clock` (monotonic seconds).
  """
  @impl true
  def init(opts) do
    govee = Keyword.fetch!(opts, :govee)
    owner = Keyword.get_lazy(opts, :owner, fn -> Ownership.owner?(@task) end)

    state = %{
      owner: owner,
      govee: govee,
      api: PlatformApi.new(govee.api_key, Keyword.get(opts, :api_req, [])),
      registry:
        DeviceRegistry.new(Map.new(govee.names, fn {mac, %{name: name}} -> {mac, name} end)),
      store: StateStore.new(govee.pending_window_seconds * 1.0),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) / 1000 end),
      send: Keyword.get(opts, :send, &Lan.send_datagram/1),
      publish: Keyword.get_lazy(opts, :publish, fn -> default_publish(owner) end),
      socket: nil,
      listen_port: Keyword.get(opts, :listen_port, Lan.listen_port()),
      listen_backoff_ms: @listen_backoff_min_ms,
      bootstrapped: false
    }

    state = if owner, do: listen(state), else: state

    send(self(), :bootstrap)
    if owner, do: send(self(), :lan_poll)
    Process.send_after(self(), :api_poll, govee.api_poll_seconds * 1000)
    Logger.info("Govee bridge: starting (#{if owner, do: "owner", else: "shadow"})")
    {:ok, state}
  end

  @doc "The port the LAN listener is bound to (tests)."
  def listen_port(server \\ __MODULE__), do: GenServer.call(server, :listen_port)

  @impl true
  def handle_call(:listen_port, _from, %{socket: nil} = state), do: {:reply, nil, state}

  def handle_call(:listen_port, _from, state),
    do: {:reply, elem(:inet.port(state.socket), 1), state}

  @impl true
  def handle_info(:bootstrap, state) do
    async(state, :refreshed, fn -> refresh(state) end)
    {:noreply, state}
  end

  def handle_info({:refreshed, result}, state) do
    state = adopt_refresh(state, result)
    {:noreply, if(state.bootstrapped, do: state, else: bootstrap(state))}
  end

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

    async(state, :api_states, fn ->
      Enum.map(devices, &{&1, PlatformApi.state(state.api, &1.sku, &1.api_id)})
    end)

    {:noreply, state}
  end

  def handle_info({:api_states, results}, state) do
    case results do
      results when is_list(results) ->
        {:noreply, Enum.reduce(results, state, &apply_api(&2, &1, true))}

      {:error, message} ->
        Logger.warning("Govee bridge: API poll failed: #{message}")
        {:noreply, state}
    end
  end

  def handle_info({:clarified, result}, state), do: {:noreply, apply_api(state, result, false)}

  def handle_info(:listen, %{socket: nil} = state), do: {:noreply, listen(state)}

  def handle_info({:udp, socket, ip, _port, payload}, %{socket: socket} = state),
    do: {:noreply, handle_datagram(state, payload, ip |> :inet.ntoa() |> List.to_string())}

  def handle_info({:set, key, payload}, %{owner: true} = state),
    do: {:noreply, on_set(state, key, payload)}

  def handle_info({:set, _key, _payload}, state), do: {:noreply, state}

  def handle_info(message, state) do
    Logger.debug("Govee bridge: ignoring #{inspect(message)}")
    {:noreply, state}
  end

  # --- Bootstrap and registry ---------------------------------------------------

  defp refresh(state) do
    scenes = fn raw ->
      PlatformApi.scenes(state.api, to_string(raw["sku"]), to_string(raw["device"]))
    end

    case PlatformApi.devices(state.api) do
      {:ok, raw} -> {:ok, DeviceRegistry.refresh(state.registry, raw, scenes)}
      {:error, message} -> {:error, message}
    end
  end

  # IPs found while the refresh ran win over the snapshot it started from.
  defp adopt_refresh(state, {:ok, registry}) do
    registry =
      Enum.reduce(DeviceRegistry.all(state.registry), registry, fn device, acc ->
        if device.ip, do: DeviceRegistry.record_lan_ip(acc, device.key, device.ip), else: acc
      end)

    %{state | registry: registry}
  end

  defp adopt_refresh(state, {:error, message}) do
    Logger.warning("Govee.DeviceRegistry: refresh failed: #{message}")
    state
  end

  defp bootstrap(state) do
    devices = DeviceRegistry.all(state.registry)

    if devices == [] do
      Logger.warning(
        "Govee bridge: no devices after refresh; retrying in #{state.govee.api_poll_seconds}s"
      )

      Process.send_after(self(), :bootstrap, state.govee.api_poll_seconds * 1000)
      state
    else
      lan(state, :discover)

      published =
        for device <- devices do
          if device.ip, do: lan(state, {:request_status, device.ip})

          publish(
            state,
            "govees/#{device.key}/config",
            RubyJSON.generate!(Messages.config_wire(device))
          )
        end

      if Enum.all?(published, &(&1 == :ok)) do
        Logger.info("Govee bridge: bootstrapped #{length(devices)} devices")
        %{state | bootstrapped: true}
      else
        Process.send_after(self(), :bootstrap, state.govee.api_poll_seconds * 1000)
        state
      end
    end
  end

  # --- LAN ----------------------------------------------------------------------

  defp listen(%{listen_port: false} = state), do: state

  # A port another process holds (a bridge not yet gone) is retried with backoff,
  # 1 s to 60 s: an owner without its listener would hear no lamp.
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
      StateStore.apply_telemetry(
        state.store,
        device.key,
        Lan.telemetry(status),
        :lan,
        state.clock.()
      )

    state = %{state | store: store}

    if result.needs_api_clarification,
      do:
        async(state, :clarified, fn ->
          {device, PlatformApi.state(state.api, device.sku, device.api_id)}
        end)

    if result.changed, do: publish_state(state, device.key, result.published)
    state
  end

  # --- API ----------------------------------------------------------------------

  defp apply_api(state, {device, {:ok, map}}, publish?) do
    case device_telemetry(map, device) do
      {:ok, telemetry} ->
        {result, store} =
          StateStore.apply_telemetry(state.store, device.key, telemetry, :api, state.clock.())

        if publish? and result.changed, do: publish_state(state, device.key, result.published)
        %{state | store: store}

      :error ->
        Logger.warning("Govee.Reconciler: API state of #{device.key} does not coerce")
        state
    end
  end

  defp apply_api(state, {device, {:error, message}}, _publish?) do
    Logger.warning("Govee.Reconciler: api state #{device.key}: #{message}")
    state
  end

  defp apply_api(state, {:error, message}, _publish?) do
    Logger.warning("Govee.Reconciler: #{message}")
    state
  end

  # Rails' to_i raised on a value no Ruby number answers; the tick skipped the lamp.
  defp device_telemetry(map, device) do
    Messages.device_telemetry(map, device.zones)
  rescue
    _ -> :error
  end

  # --- Commands -----------------------------------------------------------------

  defp on_set(state, key, payload) do
    with {:ok, %{} = verb} <- JSON.decode(payload),
         {published, store} <-
           CommandRouter.handle(
             DeviceRegistry.find(state.registry, key),
             key,
             verb,
             state.store,
             io(state),
             state.clock.()
           ) do
      if published, do: publish_state(state, key, published)
      %{state | store: store}
    else
      other ->
        Logger.warning("Govee bridge: set verb for #{key} failed: #{inspect(other)}")
        state
    end
  rescue
    error ->
      Logger.warning("Govee bridge: set verb for #{key} failed: #{Exception.message(error)}")
      state
  end

  defp io(state) do
    %{
      lan: fn command -> ok!(lan(state, command)) end,
      api: fn control -> ok!(PlatformApi.control(state.api, control)) end
    }
  end

  defp ok!({:error, reason}), do: raise(RuntimeError, inspect(reason))
  defp ok!(_), do: :ok

  # --- Effects ------------------------------------------------------------------

  defp lan(%{owner: false}, _command), do: :ok

  # Rails holding the lease (Ziwoas.Lease) refuses the datagram, never the bridge.
  defp lan(state, command) do
    state.send.(Lan.datagram(command))
  rescue
    error in Ownership.NotOwnerError ->
      Logger.error("Govee bridge: datagram refused: #{Exception.message(error)}")
      {:error, :not_owner}
  end

  defp publish_state(state, key, published) do
    case Messages.state(published) do
      {:ok, message} ->
        publish(state, "govees/#{key}/state", RubyJSON.generate!(Messages.state_wire(message)))

      :error ->
        Logger.warning("Govee bridge: state of #{key} does not coerce: #{inspect(published)}")
    end
  end

  defp publish(state, topic, payload), do: state.publish.(topic, payload)

  defp default_publish(true) do
    fn topic, payload ->
      try do
        case Mqtt.publish(@task, @client_id, topic, payload, retain: true) do
          :ok ->
            :ok

          {:error, reason} = error ->
            Logger.error("Govee bridge: publish #{topic} failed: #{inspect(reason)}")
            error
        end
      rescue
        error in Ownership.NotOwnerError ->
          Logger.error("Govee bridge: publish #{topic} refused: #{Exception.message(error)}")
          {:error, :not_owner}
      end
    end
  end

  defp default_publish(false) do
    fn topic, payload ->
      Logger.debug("Govee bridge (shadow): would publish #{topic} #{payload}")
      :ok
    end
  end

  # The task always answers, whatever ends it (a raise, an exit of a Req call, a throw).
  defp async(state, tag, fun) do
    parent = self()

    Task.start(fn ->
      result =
        try do
          fun.()
        rescue
          error -> {:error, Exception.message(error)}
        catch
          kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
        end

      send(parent, {tag, result})
    end)

    state
  end
end
