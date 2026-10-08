defmodule Ziwoas.Switching.ScheduleTickJobTest do
  use Ziwoas.DataCase

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Ziwoas.{Clock, FakeShelly, Repo, TestClock}
  alias Ziwoas.Switching
  alias Ziwoas.Switching.{Command, SchedulerState, ScheduleTickJob}

  @now "2026-06-15T18:05:00+02:00"

  setup do
    TestClock.freeze(@now)

    %{config: Ziwoas.Config.get()}
  end

  defp window!(on, off) do
    Switching.save_window("fridge", %{on_at_time: on, off_at_time: off, days: [1]})
  end

  defp watermark!(time),
    do: Repo.insert!(%SchedulerState{plug_id: "fridge", last_tick_at: Clock.parse!(time)})

  test "perform switches the edge between watermark and now and moves the watermark", ctx do
    window!("18:00", "23:00")
    watermark!("2026-06-15T17:55:00+02:00")
    FakeShelly.serve("fridge")

    ScheduleTickJob.perform(config: ctx.config, at: Clock.now())

    assert_received {:shelly_rpc, "fridge", "Switch.Set", %{on: true}}
    assert [%Command{action: :on, source: :schedule}] = Repo.all(Command)
    assert Switching.last_tick_at("fridge") == Clock.now()
  end

  test "the warning names the plug, the rule and the reason; the watermark stays", ctx do
    window!("18:00", "23:00")
    watermark!("2026-06-15T17:55:00+02:00")
    [on | _] = Repo.all(from r in Ziwoas.Switching.Rule, order_by: [desc: r.action])

    log = capture_log(fn -> ScheduleTickJob.tick(ctx.config, Clock.now()) end)

    assert log =~ "fridge"
    assert log =~ "rule #{on.id}"
    assert log =~ "offline"
    assert Repo.all(Command) == []

    assert DateTime.compare(
             Switching.last_tick_at("fridge"),
             Clock.parse!("2026-06-15T17:55:00+02:00")
           ) == :eq
  end
end
