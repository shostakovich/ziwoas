defmodule Ziwoas.Collector.MqttIntegrationTest do
  # Tortoise311 against a broker on a socket: the ingest connection subscribes and
  # writes what arrives, an owner publishes, commands reach the Govee bridge. Client
  # ids are global names, so this module runs alone. The connections' handlers write
  # from processes of Tortoise's own, hence the shared sandbox.
  use Ziwoas.DataCase

  alias Ziwoas.Collector.MqttRouter
  alias Ziwoas.{FakeMqttBroker, Mqtt, Repo, TestConfigs}
  alias Ziwoas.Lights.GoveeSubscriber
  alias Ziwoas.Plugs.{Sample, ShellyStatusHandler}

  @moduletag :capture_log
  @moduletag :shared_sandbox

  setup do
    broker = start_supervised!(FakeMqttBroker)
    %{broker: broker, mqtt: %{host: "127.0.0.1", port: FakeMqttBroker.port(broker)}}
  end

  test "the ingest connection subscribes to its handlers' topics and writes what arrives", ctx do
    handlers = [
      {ShellyStatusHandler, ShellyStatusHandler.new(TestConfigs.plugs())},
      {GoveeSubscriber, GoveeSubscriber.new()}
    ]

    start_supervised!(
      Mqtt.connection_spec(
        "ziwoas-phoenix-ingest",
        ctx.mqtt,
        {MqttRouter, handlers},
        MqttRouter.subscriptions(handlers)
      )
    )

    assert FakeMqttBroker.await(ctx.broker, &(length(FakeMqttBroker.subscriptions(&1)) == 3))
    assert FakeMqttBroker.clients(ctx.broker) == ["ziwoas-phoenix-ingest"]

    assert Enum.sort(FakeMqttBroker.subscriptions(ctx.broker)) ==
             ["govees/+/config", "govees/+/state", "shellies/+/status/switch:0"]

    FakeMqttBroker.publish(
      ctx.broker,
      "shellies/fridge/status/switch:0",
      ~s({"apower":12.5,"aenergy":{"total":3.0},"output":true})
    )

    assert FakeMqttBroker.await(ctx.broker, fn _ -> Repo.aggregate(Sample, :count) == 1 end)
    assert [%Sample{plug_id: "fridge", apower_w: 12.5, aenergy_wh: 3.0}] = Repo.all(Sample)
  end

  test "an owner publishes to the broker", ctx do
    start_supervised!(
      Mqtt.connection_spec("ziwoas-phoenix-fritz", ctx.mqtt, {Tortoise311.Handler.Logger, []})
    )

    assert FakeMqttBroker.await(ctx.broker, &(FakeMqttBroker.clients(&1) != []))

    assert :ok =
             Mqtt.publish(
               :fritz_bridge,
               "ziwoas-phoenix-fritz",
               "shellies/washer/status/switch:0",
               ~s({"apower":1.0})
             )

    assert :ok =
             Mqtt.publish(:fritz_bridge, "ziwoas-phoenix-fritz", "govees/K/state", "{}",
               retain: true
             )

    assert FakeMqttBroker.await(ctx.broker, &(length(FakeMqttBroker.published(&1)) == 2))

    assert FakeMqttBroker.published(ctx.broker) == [
             %{
               topic: "shellies/washer/status/switch:0",
               payload: ~s({"apower":1.0}),
               retain: false
             },
             %{topic: "govees/K/state", payload: "{}", retain: true}
           ]
  end

  test "a set verb on the broker reaches the Govee bridge", ctx do
    start_supervised!(
      Mqtt.connection_spec(
        "ziwoas-phoenix-govee",
        ctx.mqtt,
        {Ziwoas.Govee.CommandHandler, [self()]},
        ["govees/+/set"]
      )
    )

    assert FakeMqttBroker.await(
             ctx.broker,
             &(FakeMqttBroker.subscriptions(&1) == ["govees/+/set"])
           )

    FakeMqttBroker.publish(ctx.broker, "govees/K/set", ~s({"power":"on"}))

    assert_receive {:set, "K", ~s({"power":"on"})}, 1_000
  end
end
