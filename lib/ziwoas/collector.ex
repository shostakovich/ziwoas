defmodule Ziwoas.Collector do
  @moduledoc false
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
        # Tortoise311 crash-loops on an unreachable broker; that must never take the endpoint down.
        max_restarts: 120,
        max_seconds: 60
      )

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
