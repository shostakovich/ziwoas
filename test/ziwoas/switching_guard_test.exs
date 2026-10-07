defmodule Ziwoas.SwitchingGuardTest do
  # On a real socket: plug switches, lamp commands and the schedule tick reach the
  # broker over the command connection. The client id is a global name, so this
  # module runs alone.
  use Ziwoas.DataCase

  alias Ziwoas.{Clock, Config, FakeMqttBroker, Mqtt, TestClock}
  alias Ziwoas.Lights.Commander, as: LightCommander
  alias Ziwoas.Plugs.Plug
  alias Ziwoas.Switching.{Commander, Rules, ScheduleTickJob}

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

    # Monday 18:05 in Berlin, five minutes after a Zeitfenster's on edge.
    TestClock.freeze("2026-06-15T18:05:00+02:00")
    Rules.save_window("fridge", %{on_at_time: "18:00", off_at_time: "23:00", days: [1]})

    config = %{Config.get() | mqtt: mqtt}
    %{broker: broker, mqtt: mqtt, config: config}
  end

  defp everything(ctx) do
    ScheduleTickJob.tick(ctx.config, Clock.now())
    Commander.switch(@fridge, :off, :manual, ctx.mqtt)
    LightCommander.publish("ABCDEF01", {:power, true})
  end

  test "the commands reach the broker", ctx do
    everything(ctx)

    assert FakeMqttBroker.await(ctx.broker, &(length(FakeMqttBroker.published(&1)) == 3))

    assert Enum.map(FakeMqttBroker.published(ctx.broker), &{&1.topic, &1.payload}) == [
             {"shellies/fridge/command/switch:0", "on"},
             {"shellies/fridge/command/switch:0", "off"},
             {"govees/ABCDEF01/set", ~s({"power":"on"})}
           ]
  end
end
