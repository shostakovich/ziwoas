defmodule Ziwoas.Scheduler.ScheduleTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Scheduler.Schedule

  @zone "Europe/Berlin"

  defp utc(iso) do
    {:ok, instant, _} = DateTime.from_iso8601(iso)
    instant
  end

  defp iso(instant), do: DateTime.to_iso8601(instant)

  defp series(schedule, from, n) do
    from
    |> utc()
    |> Stream.iterate(&Schedule.next_after(schedule, &1, @zone))
    |> Enum.slice(1..n)
    |> Enum.map(&iso/1)
  end

  test "unsupported schedules are refused" do
    for schedule <- [
          {:every, 7, :minute},
          {:every, 5, :hour},
          {:every, 0, :minute},
          {:every, 1, :day},
          {:daily, "3:15"},
          "every 15 minutes"
        ] do
      refute Schedule.valid?(schedule)

      assert_raise ArgumentError, ~r/unsupported schedule/, fn ->
        Schedule.next_after(schedule, ~U[2026-10-05 10:00:00Z], @zone)
      end
    end

    assert Schedule.valid?({:every, 30, :second})
    assert Schedule.valid?({:daily, ~T[03:15:00]})
  end

  test "intervals align to the clock and fall due strictly after" do
    assert series({:every, 15, :minute}, "2026-10-05T10:00:00Z", 3) ==
             ["2026-10-05T10:15:00Z", "2026-10-05T10:30:00Z", "2026-10-05T10:45:00Z"]

    assert series({:every, 30, :second}, "2026-10-05T10:00:10Z", 2) ==
             ["2026-10-05T10:00:30Z", "2026-10-05T10:01:00Z"]

    assert series({:every, 1, :minute}, "2026-10-05T10:00:59.999999Z", 1) == [
             "2026-10-05T10:01:00Z"
           ]

    assert series({:every, 2, :minute}, "2026-10-05T10:01:00Z", 2) == [
             "2026-10-05T10:02:00Z",
             "2026-10-05T10:04:00Z"
           ]

    assert series({:every, 1, :hour}, "2026-10-05T10:20:00Z", 1) == ["2026-10-05T11:00:00Z"]
  end

  test "hourly keeps running hourly through both DST changes" do
    assert series({:every, 1, :hour}, "2026-10-24T23:30:00Z", 4) ==
             [
               "2026-10-25T00:00:00Z",
               "2026-10-25T01:00:00Z",
               "2026-10-25T02:00:00Z",
               "2026-10-25T03:00:00Z"
             ]

    assert series({:every, 1, :hour}, "2026-03-29T00:30:00Z", 2) == [
             "2026-03-29T01:00:00Z",
             "2026-03-29T02:00:00Z"
           ]

    assert series({:every, 15, :minute}, "2026-10-25T00:50:00Z", 2) == [
             "2026-10-25T01:00:00Z",
             "2026-10-25T01:15:00Z"
           ]
  end

  test "every N hours follows the local clock" do
    assert series({:every, 3, :hour}, "2026-03-28T22:30:00Z", 3) ==
             ["2026-03-28T23:00:00Z", "2026-03-29T01:00:00Z", "2026-03-29T04:00:00Z"]
  end

  test "a daily time runs once per local day, whatever the offset" do
    assert series({:daily, ~T[03:15:00]}, "2026-03-27T12:00:00Z", 3) ==
             ["2026-03-28T02:15:00Z", "2026-03-29T01:15:00Z", "2026-03-30T01:15:00Z"]

    assert series({:daily, ~T[15:45:00]}, "2026-10-24T12:00:00Z", 2) ==
             ["2026-10-24T13:45:00Z", "2026-10-25T14:45:00Z"]
  end

  test "a daily time in the spring gap runs an hour later, an ambiguous one once at its first occurrence" do
    assert series({:daily, ~T[02:30:00]}, "2026-03-28T12:00:00Z", 2) ==
             ["2026-03-29T01:30:00Z", "2026-03-30T00:30:00Z"]

    assert series({:daily, ~T[02:30:00]}, "2026-10-24T12:00:00Z", 2) ==
             ["2026-10-25T00:30:00Z", "2026-10-26T01:30:00Z"]
  end

  test "midnight and noon" do
    assert series({:daily, ~T[00:00:00]}, "2026-07-01T12:00:00Z", 1) == ["2026-07-01T22:00:00Z"]
    assert series({:daily, ~T[12:30:00]}, "2026-07-01T09:00:00Z", 1) == ["2026-07-01T10:30:00Z"]
  end
end
