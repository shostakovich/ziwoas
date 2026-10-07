defmodule Ziwoas.LocalDayTest do
  use ExUnit.Case, async: true

  alias Ziwoas.LocalDay

  @zone "Europe/Berlin"

  # Expected values from Ruby (Time.zone = "Europe/Berlin"):
  #   Time.zone.local(2026, 3, 29, 2, 30).utc   # => 2026-03-29 01:30:00 UTC (gap: 03:30 +02:00)
  #   Time.zone.local(2026, 10, 25, 2, 30).utc  # => 2026-10-25 00:30:00 UTC (ambiguous: +02:00)
  test "to_instant resolves a gap an hour later and an ambiguous time to summer time, as ActiveSupport" do
    assert LocalDay.to_instant(~N[2026-03-29 02:30:00], @zone) |> utc() ==
             ~U[2026-03-29 01:30:00Z]

    assert LocalDay.to_instant(~N[2026-10-25 02:30:00], @zone) |> utc() ==
             ~U[2026-10-25 00:30:00Z]

    assert LocalDay.to_instant(~N[2026-10-05 12:00:00], @zone) |> utc() ==
             ~U[2026-10-05 10:00:00Z]
  end

  # (Time.zone.parse(now) - n.days).utc in Ruby:
  #   2026-10-30 02:30 - 5.days  # => 2026-10-25 01:30 UTC (ambiguous: keeps now's +01:00)
  #   2026-04-03 02:30 - 5.days  # => 2026-03-29 01:30 UTC (gap: 03:30 +02:00)
  #   2026-11-01 12:00 - 30.days # => 2026-10-02 10:00 UTC
  test "advance_days keeps the local clock time, like TimeWithZone#advance(days:)" do
    assert LocalDay.advance_days(~U[2026-10-30 01:30:00.000000Z], -5, @zone) ==
             ~U[2026-10-25 01:30:00.000000Z]

    assert LocalDay.advance_days(~U[2026-04-03 00:30:00.000000Z], -5, @zone) ==
             ~U[2026-03-29 01:30:00.000000Z]

    assert LocalDay.advance_days(~U[2026-11-01 11:00:00.000000Z], -30, @zone) ==
             ~U[2026-10-02 10:00:00.000000Z]
  end

  defp utc(instant), do: DateTime.shift_zone!(instant, "Etc/UTC")
end
