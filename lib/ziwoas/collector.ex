defmodule Ziwoas.Collector do
  @moduledoc """
  The device connections as a supervision tree, one child per connection or device:

      Ziwoas.Collector (one_for_one)
      ├── Ziwoas.Shelly.Listener    Bandit on `:shelly_port`: the Shelly plugs'
      │                             outbound websockets (Ziwoas.Shelly.Connection)
      ├── Ziwoas.Solakon.Monitor    Modbus TCP (the scheduler's solakon_monitor and
      │                             solakon_snapshot jobs read through it)
      ├── Ziwoas.Fritz.Bridge ×n    one per Fritz!DECT plug, recording in-process
      ├── Ziwoas.Govee.Tasks        Task.Supervisor: the bridge's Platform API calls
      └── Ziwoas.Govee.Bridge       LAN + Platform API, reports to Ziwoas.Lights

  Each child restarts on its own; devices reconnect with backoff inside their
  process, the Shellys by themselves. The restart intensity is high enough that a
  crash-looping device never takes the tree — and with it the web endpoint's
  supervisor — down. A Shelly port already in use stops the start.
  """
  use Supervisor

  require Logger

  alias Ziwoas.{Config, Shelly}
  alias Ziwoas.Fritz.DectClient

  def start_link(opts),
    do: Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts),
    do:
      Supervisor.init(children(Keyword.fetch!(opts, :config)),
        strategy: :one_for_one,
        max_restarts: 120,
        max_seconds: 60
      )

  @doc "The children for a configuration: only what it configures."
  @spec children(Config.t()) :: [Supervisor.child_spec()]
  def children(%Config{} = config),
    do: shelly(config) ++ solakon(config) ++ fritz(config) ++ govee(config)

  defp shelly(config) do
    if Enum.any?(config.plugs, &(&1.driver == :shelly)),
      do: [Shelly.listener_spec(config, shelly_port())],
      else: []
  end

  defp shelly_port, do: Application.fetch_env!(:ziwoas, :shelly_port)

  defp solakon(%Config{solakon: nil}), do: []

  defp solakon(%Config{solakon: solakon}) do
    if solakon.monitoring_enabled do
      [{Ziwoas.Solakon.Monitor, host: solakon.host, port: solakon.port, unit_id: solakon.unit_id}]
    else
      if solakon.control_enabled,
        do:
          Logger.warning(
            "solakon: control_enabled, but monitoring_enabled is off; no control tick runs"
          )

      []
    end
  end

  defp fritz(config) do
    case Enum.filter(config.plugs, &(&1.driver == :fritz_dect)) do
      [] ->
        []

      plugs ->
        client =
          DectClient.new(
            host: config.fritz_box.host,
            user: config.fritz_box.user,
            password: config.fritz_box.password,
            timeout_s: config.fritz_poll.timeout_seconds
          )

        for plug <- plugs,
            do: {Ziwoas.Fritz.Bridge, plug: plug, client: client, poll: config.fritz_poll}
    end
  end

  defp govee(%Config{govee: nil}), do: []

  defp govee(%Config{govee: %{api_key: api_key}}) when api_key in [nil, ""] do
    Logger.warning("Govee bridge disabled: missing govee.api_key in ziwoas.yml")
    []
  end

  defp govee(%Config{govee: govee}),
    do: [
      {Task.Supervisor, name: Ziwoas.Govee.Tasks},
      {Ziwoas.Govee.Bridge, govee: govee}
    ]
end
