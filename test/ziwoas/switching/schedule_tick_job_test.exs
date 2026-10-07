defmodule Ziwoas.Switching.ScheduleTickJobTest do
  use Ziwoas.DataCase

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Ziwoas.{Clock, Repo, TestClock, TestMqtt}
  alias Ziwoas.Switching.{Command, Rules, ScheduleTickJob, SchedulerState}

  # Monday 2026-06-15 18:05 in Berlin.
  @now "2026-06-15T18:05:00+02:00"

  setup do
    TestClock.freeze(@now)
    test = self()

    TestMqtt.record(fn _client, topic, payload ->
      send(test, {:published, topic, payload})

      if String.contains?(topic, "/fridge/") and Process.get(:broker_down),
        do: {:error, :econnrefused},
        else: :ok
    end)

    # test/fixtures/ziwoas.test.yml: fridge switches.
    %{config: Ziwoas.Config.app_config()}
  end

  defp window!(on, off) do
    Rules.save_window("fridge", %{on_at_time: on, off_at_time: off, days: [1]})
  end

  defp watermark!(time),
    do: Repo.insert!(%SchedulerState{plug_id: "fridge", last_tick_at: Clock.parse!(time)})

  test "perform switches the edge between watermark and now and moves the watermark", ctx do
    window!("18:00", "23:00")
    watermark!("2026-06-15T17:55:00+02:00")

    ScheduleTickJob.perform(%{
      at: Clock.now(),
      config: ctx.config
    })

    assert_received {:published, "shellies/fridge/command/switch:0", "on"}
    assert [%Command{action: "on", source: "schedule"}] = Repo.all(Command)
    assert SchedulerState.last_tick_at("fridge") == Clock.now()
  end

  test "the warning names the plug, the rule and the reason; the watermark stays", ctx do
    window!("18:00", "23:00")
    watermark!("2026-06-15T17:55:00+02:00")
    Process.put(:broker_down, true)
    [on | _] = Repo.all(from r in Ziwoas.Switching.Rule, order_by: [desc: r.action])

    log = capture_log(fn -> ScheduleTickJob.tick(ctx.config, Clock.now()) end)

    assert log =~ "fridge"
    assert log =~ "rule #{on.id}"
    assert log =~ "econnrefused"
    assert Repo.all(Command) == []

    assert DateTime.compare(
             SchedulerState.last_tick_at("fridge"),
             Clock.parse!("2026-06-15T17:55:00+02:00")
           ) == :eq
  end
end
