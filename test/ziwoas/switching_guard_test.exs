defmodule Ziwoas.SwitchingGuardTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Clock, Config, FakeMqttBroker, Mqtt, Switching, TestClock}
  alias Ziwoas.Plugs.Plug
  alias Ziwoas.Switching.ScheduleTickJob

  @moduletag :capture_log
  @fridge %Plug{id: "fridge", role: :consumer, driver: :shelly, switchable: true}

  setup do
    broker = start_supervised!(FakeMqttBroker)

    mqtt = %Config.Mqtt{
      host: "127.0.0.1",
      port: FakeMqttBroker.port(broker),
      topic_prefix: "shellies"
    }

    start_supervised!(
      Mqtt.connection_spec(Mqtt.command_client_id(), mqtt, {Tortoise311.Handler.Logger, []})
    )

    assert FakeMqttBroker.await(
             broker,
             &(FakeMqttBroker.clients(&1) == ["ziwoas-phoenix-command"])
           )

    TestClock.freeze("2026-06-15T18:05:00+02:00")
    Switching.save_window("fridge", %{on_at_time: "18:00", off_at_time: "23:00", days: [1]})

    config = %{Config.get() | mqtt: mqtt}
    %{broker: broker, mqtt: mqtt, config: config}
  end

  test "the commands reach the broker", ctx do
    ScheduleTickJob.tick(ctx.config, Clock.now())
    Switching.switch(@fridge, :off, :manual, ctx.mqtt)

    assert FakeMqttBroker.await(ctx.broker, &(length(FakeMqttBroker.published(&1)) == 2))

    assert Enum.map(FakeMqttBroker.published(ctx.broker), &{&1.topic, &1.payload}) == [
             {"shellies/fridge/command/switch:0", "on"},
             {"shellies/fridge/command/switch:0", "off"}
           ]
  end
end
