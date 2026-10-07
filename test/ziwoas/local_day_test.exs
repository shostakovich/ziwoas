defmodule Ziwoas.LocalDayTest do
  use ExUnit.Case, async: true

  alias Ziwoas.LocalDay

  @zone "Europe/Berlin"

  test "to_instant resolves a gap an hour later and an ambiguous time to summer time" do
    assert LocalDay.to_instant(~N[2026-03-29 02:30:00], @zone) |> utc() ==
             ~U[2026-03-29 01:30:00Z]

    assert LocalDay.to_instant(~N[2026-10-25 02:30:00], @zone) |> utc() ==
             ~U[2026-10-25 00:30:00Z]

    assert LocalDay.to_instant(~N[2026-10-05 12:00:00], @zone) |> utc() ==
             ~U[2026-10-05 10:00:00Z]
  end

  test "advance_days keeps the local clock time" do
    assert LocalDay.advance_days(~U[2026-10-30 01:30:00.000000Z], -5, @zone) ==
             ~U[2026-10-25 01:30:00.000000Z]

    assert LocalDay.advance_days(~U[2026-04-03 00:30:00.000000Z], -5, @zone) ==
             ~U[2026-03-29 01:30:00.000000Z]

    assert LocalDay.advance_days(~U[2026-11-01 11:00:00.000000Z], -30, @zone) ==
             ~U[2026-10-02 10:00:00.000000Z]
  end

  defp utc(instant), do: DateTime.shift_zone!(instant, "Etc/UTC")
end
