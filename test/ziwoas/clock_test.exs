defmodule Ziwoas.ClockTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Clock

  setup do
    on_exit(&Clock.unfreeze/0)
  end

  test "reads the system clock unless frozen" do
    before = DateTime.utc_now()
    now = Clock.now()
    assert DateTime.compare(now, before) != :lt
    assert now.time_zone == "Etc/UTC"
    assert {_, 6} = now.microsecond
  end

  test "a frozen instant stands still and is seen in UTC, local zones and Unix seconds" do
    Clock.freeze("2026-10-05T12:00:00+02:00")

    assert Clock.now() == ~U[2026-10-05 10:00:00.000000Z]
    assert Clock.now() == Clock.now()
    assert Clock.unix_now() == 1_791_194_400
    assert Clock.now("Europe/Berlin").hour == 12
    assert Clock.today("Europe/Berlin") == ~D[2026-10-05]
  end

  test "today is the local date: before 02:00 Berlin the UTC date is still yesterday" do
    Clock.freeze(~U[2026-10-04 22:30:00Z])

    assert Clock.today("Europe/Berlin") == ~D[2026-10-05]
    assert Clock.utc_today() == ~D[2026-10-04]
  end

  test "processes started by a frozen process see its instant" do
    Clock.freeze(~U[2026-01-01 00:00:00Z])
    task = Task.async(fn -> Clock.now() end)
    assert Task.await(task) == ~U[2026-01-01 00:00:00.000000Z]
  end

  test "unfreeze returns to the system clock" do
    Clock.freeze(~U[2000-01-01 00:00:00Z])
    Clock.unfreeze()
    assert Clock.now().year >= 2026
  end

  test "rejects an instant without offset" do
    assert_raise ArgumentError, fn -> Clock.freeze("2026-10-05T12:00:00") end
  end
end
