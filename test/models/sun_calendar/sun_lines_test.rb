require "test_helper"

class SunCalendar::SunLinesTest < ActiveSupport::TestCase
  cover "SunCalendar::SunLines*"

  BERLIN = { timezone: "Europe/Berlin", lat: 52.52, lon: 13.405 }.freeze

  def lines_for(year, **location) = SunCalendar::SunLines.new(location: Location.new(**location)).build(year)

  test "gives one point per day plus one for each daylight saving change" do
    lines = lines_for(2026, **BERLIN)

    assert_equal 365 + 2, lines.rise.length
    assert_equal 365 + 2, lines.set.length
    assert_equal 365 + 2, lines.noon.length
    assert_equal 1, lines.rise.first.first
    assert_equal 365, lines.rise.last.first
  end

  test "steps by an hour on the spring change instead of ramping" do
    lines = lines_for(2026, **BERLIN)
    doy = Date.new(2026, 3, 29).yday

    before, after = lines.rise.select { |point| point.first == doy }

    assert_in_delta 1.0, after.last - before.last, 0.01
  end

  test "takes the winter offset back on the autumn change" do
    lines = lines_for(2026, **BERLIN)
    doy = Date.new(2026, 10, 25).yday

    before, after = lines.set.select { |point| point.first == doy }

    assert_in_delta(-1.0, after.last - before.last, 0.01)
  end

  test "puts solar noon midway between sunrise and sunset" do
    lines = lines_for(2026, **BERLIN)
    doy = Date.new(2026, 6, 21).yday
    rise = lines.rise.find { |point| point.first == doy }.last
    set = lines.set.find { |point| point.first == doy }.last

    assert_in_delta (rise + set) / 2, lines.noon.find { |point| point.first == doy }.last, 0.001
  end

  test "reads the summer sunrise off the local clock" do
    lines = lines_for(2026, **BERLIN)
    doy = Date.new(2026, 6, 21).yday

    assert_in_delta 4.75, lines.rise.find { |point| point.first == doy }.last, 0.2
    assert_in_delta 21.55, lines.set.find { |point| point.first == doy }.last, 0.2
  end

  test "skips the polar days that have no sunrise" do
    lines = lines_for(2026, timezone: "Europe/Oslo", lat: 78.22, lon: 15.65)

    assert_operator lines.rise.length, :<, 365
    assert_predicate lines.rise, :any?
    assert lines.rise.none? { |point| point.first == Date.new(2026, 6, 21).yday }
  end

  test "has nothing to draw for a location without coordinates" do
    lines = lines_for(2026, timezone: "Europe/Berlin")

    assert_predicate lines, :empty?
    assert_empty lines.set
    assert_empty lines.noon
  end

  test "covers the leap day" do
    lines = lines_for(2024, **BERLIN)

    assert_equal 366 + 2, lines.rise.length
    assert_equal 366, lines.rise.last.first
  end

  # SunCalc's own sunrise/sunset always go nil together, so only a fake Sun can split them.
  def fake_sun(sunrise:, sunset:)
    Class.new do
      define_method(:sunrise) { |_date| sunrise }
      define_method(:sunset) { |_date| sunset }
    end.new
  end

  test "has no events when only the sunset is missing" do
    location = Location.new(**BERLIN)
    sun = fake_sun(sunrise: Time.utc(2026, 6, 21, 4), sunset: nil)
    location.define_singleton_method(:sun) { sun }
    sun_lines = SunCalendar::SunLines.new(location: location)

    assert_nil sun_lines.send(:events, Date.new(2026, 6, 21))
  end

  test "has no events when only the sunrise is missing" do
    location = Location.new(**BERLIN)
    sun = fake_sun(sunrise: nil, sunset: Time.utc(2026, 6, 21, 21))
    location.define_singleton_method(:sun) { sun }
    sun_lines = SunCalendar::SunLines.new(location: location)

    assert_nil sun_lines.send(:events, Date.new(2026, 6, 21))
  end
end
