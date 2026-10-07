defmodule Ziwoas.Collector do
  @moduledoc """
  The device connections as a supervision tree, one child per connection or device:

      Ziwoas.Collector (one_for_one)
      ├── ziwoas-phoenix-ingest     MQTT: Ziwoas.Collector.MqttRouter with
      │                             ShellyStatusHandler
      ├── Ziwoas.Solakon.Monitor    Modbus TCP (the scheduler's solakon_monitor and
      │                             solakon_snapshot jobs read through it)
      ├── ziwoas-phoenix-fritz      MQTT publisher for the Fritz bridges
      ├── Ziwoas.Fritz.Bridge ×n    one per Fritz!DECT plug
      ├── Ziwoas.Govee.Tasks        Task.Supervisor: the bridge's Platform API calls
      ├── Ziwoas.Govee.Bridge       LAN + Platform API, reports to Ziwoas.Lights
      └── ziwoas-phoenix-command    MQTT publisher: plug switches

  Each child restarts on its own; devices reconnect with backoff inside their
  process. Tortoise311 stops a connection on some network errors (an unreachable
  broker host) and comes back a second after its restart, so the restart intensity
  is high enough that a crash-looping connection never takes the tree — and with it
  the web endpoint's supervisor — down.
  """
  use Supervisor

  require Logger

  alias Ziwoas.Collector.MqttRouter
  alias Ziwoas.{Config, Mqtt}
  alias Ziwoas.Fritz.DectClient
  alias Ziwoas.Plugs.ShellyStatusHandler

  @ingest_client_id "ziwoas-phoenix-ingest"

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
    do:
      mqtt_ingest(config) ++ solakon(config) ++ fritz(config) ++ govee(config) ++ commands(config)

  defp mqtt_ingest(config) do
    handlers = [{ShellyStatusHandler, ShellyStatusHandler.new(config)}]

    [
      Mqtt.connection_spec(
        @ingest_client_id,
        config.mqtt,
        {MqttRouter, handlers},
        MqttRouter.subscriptions(handlers)
      )
    ]
  end

  defp commands(config),
    do: [
      Mqtt.connection_spec(
        Mqtt.command_client_id(),
        config.mqtt,
        {Tortoise311.Handler.Logger, []}
      )
    ]

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

        publisher =
          Mqtt.connection_spec(
            Ziwoas.Fritz.Bridge.client_id(),
            config.mqtt,
            {Tortoise311.Handler.Logger, []}
          )

        [publisher] ++
          for plug <- plugs do
            {Ziwoas.Fritz.Bridge,
             plug: plug,
             client: client,
             poll: config.fritz_poll,
             topic_prefix: config.mqtt.topic_prefix}
          end
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
