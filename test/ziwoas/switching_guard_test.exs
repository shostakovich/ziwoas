defmodule Ziwoas.SwitchingGuardTest do
  # Phase 6's promise on a real socket: the command connection to a broker is up, and
  # still nothing a dry run, or a task Rails owns, does reaches it — plug switches,
  # lamp commands and the schedule tick alike. Only the owner publishes. The client id
  # is a global name, so this module runs alone.
  use Ziwoas.DataCase, async: false

  alias Ziwoas.{Clock, Config, FakeMqttBroker, Mqtt, Ownership, Repo}
  alias Ziwoas.Lights.Commander, as: LightCommander
  alias Ziwoas.Ownership.NotOwnerError
  alias Ziwoas.Plugs.Plug
  alias Ziwoas.Switching.{Command, Commander, Rules, ScheduleTickJob}

  @moduletag :capture_log
  @fridge %Plug{id: "fridge", role: :consumer, driver: :shelly, switchable: true}

  setup %{repo: repo} do
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
    Clock.freeze("2026-06-15T18:05:00+02:00")
    Repo.put_writer(:main, repo)
    Repo.put_writer(:shadow, repo)
    Ownership.override(%{switch_schedule: :phoenix})
    Rules.save_window("fridge", %{on_at_time: "18:00", off_at_time: "23:00", days: [1]})
    on_exit(&Ownership.clear_override/0)

    config = %{Config.app_config() | mqtt: mqtt}
    %{broker: broker, mqtt: mqtt, config: config}
  end

  defp everything(ctx) do
    ScheduleTickJob.tick(ctx.config, Clock.now())
    Commander.switch(@fridge, :off, :manual, ctx.mqtt)
    LightCommander.publish("ABCDEF01", {:power, true})
  end

  test "as owner the commands reach the broker", ctx do
    Ownership.override(%{switching: :phoenix, lights: :phoenix})
    everything(ctx)

    assert FakeMqttBroker.await(ctx.broker, &(length(FakeMqttBroker.published(&1)) == 3))

    assert Enum.map(FakeMqttBroker.published(ctx.broker), &{&1.topic, &1.payload}) == [
             {"shellies/fridge/command/switch:0", "on"},
             {"shellies/fridge/command/switch:0", "off"},
             {"govees/ABCDEF01/set", ~s({"power":"on"})}
           ]
  end

  test "a dry run decides and records, but nothing reaches the broker", ctx do
    Ownership.override(%{switching: :dry_run, lights: :dry_run})
    everything(ctx)

    assert [%Command{source: "schedule"}, %Command{source: "manual"}] = Repo.all(Command)

    assert_raise NotOwnerError, fn ->
      Mqtt.publish(:switching, Mqtt.command_client_id(), "shellies/fridge/command/switch:0", "on")
    end

    assert_raise NotOwnerError, fn ->
      Mqtt.publish(:lights, Mqtt.command_client_id(), "govees/ABCDEF01/set", "{}")
    end

    Process.sleep(100)
    assert FakeMqttBroker.published(ctx.broker) == []
  end

  test "while Rails owns the tasks every path raises before the socket", ctx do
    Ownership.override(%{})

    assert_raise NotOwnerError, fn -> Commander.switch(@fridge, :on, :manual, ctx.mqtt) end
    assert_raise NotOwnerError, fn -> LightCommander.publish("ABCDEF01", {:power, true}) end
    assert_raise NotOwnerError, fn -> ScheduleTickJob.tick(ctx.config, Clock.now()) end

    Process.sleep(100)
    assert FakeMqttBroker.published(ctx.broker) == []
    assert Repo.all(Command) == []
  end
end
