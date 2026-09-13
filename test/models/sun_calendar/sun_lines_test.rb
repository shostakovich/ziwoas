require "test_helper"

class SunCalendar::SunLinesTest < ActiveSupport::TestCase
  cover "SunCalendar::SunLines*"

  BERLIN = { zone: "Europe/Berlin", lat: 52.52, lon: 13.405 }.freeze

  test "gives one point per day plus one for each daylight saving change" do
    lines = SunCalendar::SunLines.new(**BERLIN).build(2026)

    assert_equal 365 + 2, lines.rise.length
    assert_equal 365 + 2, lines.set.length
    assert_equal 365 + 2, lines.noon.length
    assert_equal 1, lines.rise.first.first
    assert_equal 365, lines.rise.last.first
  end

  test "steps by an hour on the spring change instead of ramping" do
    lines = SunCalendar::SunLines.new(**BERLIN).build(2026)
    doy = Date.new(2026, 3, 29).yday

    before, after = lines.rise.select { |point| point.first == doy }

    assert_in_delta 1.0, after.last - before.last, 0.01
  end

  test "takes the winter offset back on the autumn change" do
    lines = SunCalendar::SunLines.new(**BERLIN).build(2026)
    doy = Date.new(2026, 10, 25).yday

    before, after = lines.set.select { |point| point.first == doy }

    assert_in_delta(-1.0, after.last - before.last, 0.01)
  end

  test "puts solar noon midway between sunrise and sunset" do
    lines = SunCalendar::SunLines.new(**BERLIN).build(2026)
    doy = Date.new(2026, 6, 21).yday
    rise = lines.rise.find { |point| point.first == doy }.last
    set = lines.set.find { |point| point.first == doy }.last

    assert_in_delta (rise + set) / 2, lines.noon.find { |point| point.first == doy }.last, 0.001
  end

  test "reads the summer sunrise off the local clock" do
    lines = SunCalendar::SunLines.new(**BERLIN).build(2026)
    doy = Date.new(2026, 6, 21).yday

    assert_in_delta 4.75, lines.rise.find { |point| point.first == doy }.last, 0.2
    assert_in_delta 21.55, lines.set.find { |point| point.first == doy }.last, 0.2
  end

  test "skips the polar days that have no sunrise" do
    lines = SunCalendar::SunLines.new(zone: "Europe/Oslo", lat: 78.22, lon: 15.65).build(2026)

    assert_operator lines.rise.length, :<, 365
    assert_predicate lines.rise, :any?
    assert lines.rise.none? { |point| point.first == Date.new(2026, 6, 21).yday }
  end

  test "has nothing to draw without a location" do
    without_lat = SunCalendar::SunLines.new(zone: "Europe/Berlin", lat: nil, lon: 13.405).build(2026)
    without_lon = SunCalendar::SunLines.new(zone: "Europe/Berlin", lat: 52.52, lon: nil).build(2026)

    assert_predicate without_lat, :empty?
    assert_empty without_lat.set
    assert_empty without_lat.noon
    assert_predicate without_lon, :empty?
    assert_empty without_lon.set
    assert_empty without_lon.noon
  end

  test "covers the leap day" do
    lines = SunCalendar::SunLines.new(**BERLIN).build(2024)

    assert_equal 366 + 2, lines.rise.length
    assert_equal 366, lines.rise.last.first
  end
end
