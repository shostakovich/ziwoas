defmodule Ziwoas.Scheduler.ScheduleTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Scheduler.Schedule

  @zone "Europe/Berlin"

  defp utc(iso) do
    {:ok, instant, _} = DateTime.from_iso8601(iso)
    instant
  end

  defp iso(instant), do: DateTime.to_iso8601(instant)

  # The next `n` due instants after `from`, as UTC ISO strings.
  defp series(text, from, n) do
    schedule = Schedule.parse!(text)

    from
    |> utc()
    |> Stream.iterate(&Schedule.next_after(schedule, &1, @zone))
    |> Enum.slice(1..n)
    |> Enum.map(&iso/1)
  end

  test "unsupported schedules are refused" do
    for text <- [
          "every 7 minutes",
          "every 5 hours",
          "every day",
          "at 25:00 every day",
          "at 13:00pm every day",
          "every hour at minute 60",
          "every 0 minutes",
          "hourly",
          "*/5 * * * *"
        ] do
      assert_raise ArgumentError, ~r/unsupported schedule/, fn -> Schedule.parse!(text) end
    end
  end

  test "intervals align to the clock and fall due strictly after" do
    assert series("every 15 minutes", "2026-10-05T10:00:00Z", 3) ==
             ["2026-10-05T10:15:00Z", "2026-10-05T10:30:00Z", "2026-10-05T10:45:00Z"]

    assert series("every 30 seconds", "2026-10-05T10:00:10Z", 2) ==
             ["2026-10-05T10:00:30Z", "2026-10-05T10:01:00Z"]

    assert series("every minute", "2026-10-05T10:00:59.999999Z", 1) == ["2026-10-05T10:01:00Z"]

    assert series("every 2 minutes", "2026-10-05T10:01:00Z", 2) == [
             "2026-10-05T10:02:00Z",
             "2026-10-05T10:04:00Z"
           ]

    assert series("every hour", "2026-10-05T10:20:00Z", 1) == ["2026-10-05T11:00:00Z"]

    assert series("every hour at minute 12", "2026-10-05T10:12:00Z", 2) == [
             "2026-10-05T11:12:00Z",
             "2026-10-05T12:12:00Z"
           ]
  end

  test "hourly keeps running hourly through both DST changes" do
    # Autumn: 02:00–03:00 local happens twice (00:00Z and 01:00Z), both run.
    assert series("every hour", "2026-10-24T23:30:00Z", 4) ==
             [
               "2026-10-25T00:00:00Z",
               "2026-10-25T01:00:00Z",
               "2026-10-25T02:00:00Z",
               "2026-10-25T03:00:00Z"
             ]

    # Spring: 02:00 local does not exist; one real hour still passes per run.
    assert series("every hour", "2026-03-29T00:30:00Z", 2) == [
             "2026-03-29T01:00:00Z",
             "2026-03-29T02:00:00Z"
           ]

    assert series("every 15 minutes", "2026-10-25T00:50:00Z", 2) == [
             "2026-10-25T01:00:00Z",
             "2026-10-25T01:15:00Z"
           ]
  end

  test "every N hours follows the local clock" do
    # 0, 3, 6 local: on the spring day 00:00 CET is 23:00Z, 03:00 CEST is 01:00Z.
    assert series("every 3 hours", "2026-03-28T22:30:00Z", 3) ==
             ["2026-03-28T23:00:00Z", "2026-03-29T01:00:00Z", "2026-03-29T04:00:00Z"]
  end

  test "a daily time runs once per local day, whatever the offset" do
    assert series("at 3:15am every day", "2026-03-27T12:00:00Z", 3) ==
             ["2026-03-28T02:15:00Z", "2026-03-29T01:15:00Z", "2026-03-30T01:15:00Z"]

    assert series("every day at 15:45", "2026-10-24T12:00:00Z", 2) ==
             ["2026-10-24T13:45:00Z", "2026-10-25T14:45:00Z"]
  end

  test "a daily time in the spring gap runs an hour later, an ambiguous one once at its first occurrence" do
    assert series("at 2:30am every day", "2026-03-28T12:00:00Z", 2) ==
             ["2026-03-29T01:30:00Z", "2026-03-30T00:30:00Z"]

    assert series("at 2:30am every day", "2026-10-24T12:00:00Z", 2) ==
             ["2026-10-25T00:30:00Z", "2026-10-26T01:30:00Z"]
  end

  test "12am and 12pm" do
    assert series("at 12:00am every day", "2026-07-01T12:00:00Z", 1) == ["2026-07-01T22:00:00Z"]
    assert series("at 12:30pm every day", "2026-07-01T09:00:00Z", 1) == ["2026-07-01T10:30:00Z"]
  end
end
