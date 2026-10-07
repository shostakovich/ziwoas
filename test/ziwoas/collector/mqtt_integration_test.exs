defmodule Ziwoas.Collector.MqttIntegrationTest do
  use Ziwoas.DataCase

  alias Ziwoas.Collector.MqttRouter
  alias Ziwoas.{FakeMqttBroker, Mqtt, Repo, TestConfigs}
  alias Ziwoas.Plugs.{Sample, ShellyStatusHandler}

  @moduletag :capture_log
  @moduletag :shared_sandbox

  setup do
    broker = start_supervised!(FakeMqttBroker)
    %{broker: broker, mqtt: %{host: "127.0.0.1", port: FakeMqttBroker.port(broker)}}
  end

  test "the ingest connection subscribes to its handlers' topics and writes what arrives", ctx do
    handlers = [{ShellyStatusHandler, ShellyStatusHandler.new(TestConfigs.plugs())}]

    start_supervised!(
      Mqtt.connection_spec(
        "ziwoas-phoenix-ingest",
        ctx.mqtt,
        {MqttRouter, handlers},
        MqttRouter.subscriptions(handlers)
      )
    )

    assert FakeMqttBroker.await(ctx.broker, &(length(FakeMqttBroker.subscriptions(&1)) == 1))
    assert FakeMqttBroker.clients(ctx.broker) == ["ziwoas-phoenix-ingest"]
    assert FakeMqttBroker.subscriptions(ctx.broker) == ["shellies/+/status/switch:0"]

    FakeMqttBroker.publish(
      ctx.broker,
      "shellies/fridge/status/switch:0",
      ~s({"apower":12.5,"aenergy":{"total":3.0},"output":true})
    )

    assert FakeMqttBroker.await(ctx.broker, fn _ -> Repo.aggregate(Sample, :count) == 1 end)
    assert [%Sample{plug_id: "fridge", apower_w: 12.5, aenergy_wh: 3.0}] = Repo.all(Sample)
  end

  test "a publisher connection publishes to the broker", ctx do
    start_supervised!(
      Mqtt.connection_spec(Mqtt.command_client_id(), ctx.mqtt, {Tortoise311.Handler.Logger, []})
    )

    assert FakeMqttBroker.await(ctx.broker, &(FakeMqttBroker.clients(&1) != []))

    assert :ok = Mqtt.publish(Mqtt.command_client_id(), "shellies/washer/command/switch:0", "on")

    assert FakeMqttBroker.await(ctx.broker, &(FakeMqttBroker.published(&1) != []))

    assert FakeMqttBroker.published(ctx.broker) == [
             %{topic: "shellies/washer/command/switch:0", payload: "on", retain: false}
           ]
  end
end
