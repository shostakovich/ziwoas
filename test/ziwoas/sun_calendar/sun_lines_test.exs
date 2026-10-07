defmodule Ziwoas.SunCalendar.SunLinesTest do
  # Mirrors test/models/sun_calendar/sun_lines_test.rb.
  use ExUnit.Case, async: true

  alias Ziwoas.Location
  alias Ziwoas.SunCalendar.{Lines, SunLines}

  defp lines(year, zone \\ "Europe/Berlin", lat \\ 52.52, lon \\ 13.405),
    do: SunLines.build(Location.new(zone, lat: lat, lon: lon), year)

  defp on(points, date), do: for({doy, hour} <- points, doy == Date.day_of_year(date), do: hour)

  test "gives one point per day plus one for each daylight saving change" do
    lines = lines(2026)

    assert Enum.map([lines.rise, lines.set, lines.noon], &length/1) == [367, 367, 367]
    assert elem(hd(lines.rise), 0) == 1
    assert elem(List.last(lines.rise), 0) == 365
  end

  test "steps by an hour on either change instead of ramping" do
    lines = lines(2026)

    assert [earlier, later] = on(lines.rise, ~D[2026-03-29])
    assert_in_delta later - earlier, 1.0, 0.01
    assert [earlier, later] = on(lines.set, ~D[2026-10-25])
    assert_in_delta later - earlier, -1.0, 0.01
  end

  test "puts solar noon midway and reads the summer sunrise off the local clock" do
    lines = lines(2026)
    [rise] = on(lines.rise, ~D[2026-06-21])
    [set] = on(lines.set, ~D[2026-06-21])

    assert on(lines.noon, ~D[2026-06-21]) == [(rise + set) / 2]
    assert_in_delta rise, 4.75, 0.2
    assert_in_delta set, 21.55, 0.2
  end

  test "skips the polar days, has nothing without coordinates, covers the leap day" do
    polar = lines(2026, "Europe/Oslo", 78.22, 15.65)
    assert length(polar.rise) < 365 and polar.rise != []
    assert on(polar.rise, ~D[2026-06-21]) == []

    assert Lines.empty?(lines(2026, "Europe/Berlin", nil, nil))

    leap = lines(2024)
    assert length(leap.rise) == 368
    assert elem(List.last(leap.rise), 0) == 366
  end
end
