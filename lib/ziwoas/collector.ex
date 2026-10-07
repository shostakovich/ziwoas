defmodule Ziwoas.Collector do
  @moduledoc """
  Rails' `bin/ziwoas_collector` (`Collector::Assembly`) as a supervision tree: one
  child per connection or device, each started only while its ownership task runs
  in Phoenix (`shadow` or `phoenix`):

      Ziwoas.Collector (one_for_one)
      ├── ziwoas-phoenix-ingest     MQTT: Ziwoas.Collector.MqttRouter with
      │                             ShellyStatusHandler (plug_ingest) and
      │                             GoveeSubscriber (light_ingest)
      ├── Ziwoas.Solakon.Monitor    Modbus TCP (solakon_monitor; the scheduler's
      │                             solakon_monitor/solakon_snapshot jobs read through it)
      ├── ziwoas-phoenix-fritz      MQTT publisher (fritz_bridge as owner)
      ├── Ziwoas.Fritz.Bridge ×n    one per Fritz!DECT plug (fritz_bridge)
      ├── ziwoas-phoenix-govee      MQTT: govees/+/set in, state out (govee_bridge as owner)
      ├── Ziwoas.Govee.Bridge       LAN + Platform API (govee_bridge)
      └── ziwoas-phoenix-command    MQTT publisher: plug switches and lamp commands
                                    (switching or lights as owner)

  Each child restarts on its own; devices reconnect with backoff inside their
  process. Tortoise311 stops a connection on some network errors (an unreachable
  broker host) and comes back a second after its restart, so the restart intensity
  is high enough that a crash-looping connection never takes the tree — and with it
  the web endpoint's supervisor — down. Owners are read at boot, as everywhere.
  """
  use Supervisor

  require Logger

  alias Ziwoas.{Config, Mqtt, Ownership}
  alias Ziwoas.Collector.MqttRouter
  alias Ziwoas.Fritz.DectClient
  alias Ziwoas.Lights.GoveeSubscriber
  alias Ziwoas.Plugs.ShellyStatusHandler

  @ingest_client_id "ziwoas-phoenix-ingest"

  def start_link(opts),
    do: Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts),
    do:
      Supervisor.init(children(Keyword.fetch!(opts, :config), Keyword.fetch!(opts, :owners)),
        strategy: :one_for_one,
        max_restarts: 120,
        max_seconds: 60
      )

  @doc "The children for a configuration and its owners (empty when Phoenix runs no ingest)."
  @spec children(Config.t(), Ownership.owners()) :: [Supervisor.child_spec()]
  def children(%Config{} = config, owners) do
    runs? = &(Map.fetch!(owners, &1) != :rails)
    owner? = &(Map.fetch!(owners, &1) == :phoenix)

    mqtt_ingest(config, runs?) ++
      solakon(config, runs?, owner?) ++
      fritz(config, runs?, owner?) ++ govee(config, runs?, owner?) ++ commands(config, owner?)
  end

  # Plug switches and lamp commands publish over one connection, as owner only: a dry
  # run decides and records, but has nothing to send.
  defp commands(config, owner?) do
    if owner?.(:switching) or owner?.(:lights),
      do: [
        Mqtt.connection_spec(
          Mqtt.command_client_id(),
          config.mqtt,
          {Tortoise311.Handler.Logger, []}
        )
      ],
      else: []
  end

  defp mqtt_ingest(config, runs?) do
    handlers =
      [
        runs?.(:plug_ingest) &&
          {ShellyStatusHandler, ShellyStatusHandler.new(config)},
        runs?.(:light_ingest) && {GoveeSubscriber, GoveeSubscriber.new()}
      ]
      |> Enum.filter(& &1)

    if handlers == [],
      do: [],
      else: [
        Mqtt.connection_spec(
          @ingest_client_id,
          config.mqtt,
          {MqttRouter, handlers},
          MqttRouter.subscriptions(handlers)
        )
      ]
  end

  defp solakon(%Config{solakon: nil}, _runs?, _owner?), do: []

  defp solakon(%Config{solakon: solakon}, runs?, owner?) do
    # The tick runs on the monitor's readings. The ownership validation pairs the two
    # tasks; the config may still switch the monitoring off.
    if runs?.(:solakon_control) and solakon.control_enabled and not solakon.monitoring_enabled,
      do:
        Logger.warning(
          "solakon_control: runs in Phoenix, but solakon.monitoring_enabled is off; no control tick runs"
        )

    if runs?.(:solakon_monitor) and solakon.monitoring_enabled do
      [
        {Ziwoas.Solakon.Monitor,
         host: solakon.host,
         port: solakon.port,
         unit_id: solakon.unit_id,
         keep_open: owner?.(:solakon_monitor)}
      ]
    else
      []
    end
  end

  defp fritz(config, runs?, owner?) do
    plugs = Enum.filter(config.plugs, &(&1.driver == :fritz_dect))

    if plugs == [] or not runs?.(:fritz_bridge) do
      []
    else
      publisher =
        if owner?.(:fritz_bridge),
          do: [
            Mqtt.connection_spec(
              Ziwoas.Fritz.Bridge.client_id(),
              config.mqtt,
              {Tortoise311.Handler.Logger, []}
            )
          ],
          else: []

      client =
        DectClient.new(
          host: config.fritz_box.host,
          user: config.fritz_box.user,
          password: config.fritz_box.password,
          timeout_s: config.fritz_poll.timeout_seconds
        )

      publisher ++
        for plug <- plugs do
          {Ziwoas.Fritz.Bridge,
           plug: plug,
           client: client,
           poll: config.fritz_poll,
           topic_prefix: config.mqtt.topic_prefix,
           owner: owner?.(:fritz_bridge)}
        end
    end
  end

  defp govee(%Config{govee: nil}, _runs?, _owner?), do: []

  defp govee(%Config{govee: govee} = config, runs?, owner?) do
    cond do
      not runs?.(:govee_bridge) ->
        []

      govee.api_key in [nil, ""] ->
        Logger.warning("Govee bridge disabled: missing govee.api_key in ziwoas.yml")
        []

      owner?.(:govee_bridge) ->
        [
          {Ziwoas.Govee.Bridge, govee: govee, owner: true},
          Mqtt.connection_spec(
            Ziwoas.Govee.Bridge.client_id(),
            config.mqtt,
            {Ziwoas.Govee.CommandHandler, [Ziwoas.Govee.Bridge]},
            ["govees/+/set"]
          )
        ]

      true ->
        [{Ziwoas.Govee.Bridge, govee: govee, owner: false}]
    end
  end
end
