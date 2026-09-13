require "test_helper"

class SunTest < ActiveSupport::TestCase
  cover "Sun*"

  BERLIN = Location.new(timezone: "Europe/Berlin", lat: 52.52, lon: 13.405)
  LONGYEARBYEN = Location.new(timezone: "Europe/Oslo", lat: 78.22, lon: 15.65)
  TOKYO = Location.new(timezone: "Asia/Tokyo", lat: 35.68, lon: 139.77)
  NOWHERE = Location.new(timezone: "Europe/Berlin")

  MIDSUMMER = Date.new(2026, 6, 21)
  MIDWINTER = Date.new(2026, 12, 21)

  test "puts the summer sun in the south at its highest" do
    # Solar noon in Berlin, some minutes ahead of the clock's twelve.
    noon = BERLIN.sun.position(Time.utc(2026, 6, 21, 11, 7))

    assert_in_delta 180.0, noon.azimuth, 1.0
    assert_in_delta 61.0, noon.elevation, 1.0
  end

  test "puts the sun below the horizon at night" do
    assert_operator BERLIN.sun.position(Time.utc(2026, 6, 21, 0)).elevation, :<, 0
  end

  test "reads sunrise and sunset off the local clock" do
    sunrise = BERLIN.sun.sunrise(MIDSUMMER)
    sunset = BERLIN.sun.sunset(MIDSUMMER)

    assert_equal "Europe/Berlin", sunrise.time_zone.name
    assert_in_delta 4.75, sunrise.hour + sunrise.min / 60.0, 0.2
    assert_in_delta 21.55, sunset.hour + sunset.min / 60.0, 0.2
  end

  test "has no sunrise and no sunset on a polar day" do
    assert_nil LONGYEARBYEN.sun.sunrise(MIDSUMMER)
    assert_nil LONGYEARBYEN.sun.sunset(MIDSUMMER)
  end

  test "calls the hours between sunrise and sunset day and the rest night" do
    assert BERLIN.sun.daytime?(Time.utc(2026, 6, 21, 10))
    refute BERLIN.sun.daytime?(Time.utc(2026, 6, 21, 0))
  end

  test "samples the path every quarter hour the sun is up" do
    hours = BERLIN.sun.path(MIDSUMMER).map(&:hour)

    assert_equal 66, hours.length
    assert_in_delta 0.25, hours[1] - hours[0]
    assert_equal hours, hours.sort
  end

  test "keeps the path above the horizon and moves it from east to west" do
    waypoints = BERLIN.sun.path(MIDSUMMER)

    assert waypoints.all? { |waypoint| waypoint.elevation.positive? }
    assert_equal waypoints.map(&:azimuth), waypoints.map(&:azimuth).sort
  end

  test "counts the path's hours off the local midnight, not off UTC" do
    noon = BERLIN.sun.path(MIDSUMMER).find { |waypoint| waypoint.hour == 12.0 }

    assert_in_delta 149.6, noon.azimuth, 1.0
    assert_in_delta 58.0, noon.elevation, 2.0
  end

  test "draws a shorter path in winter than in summer" do
    assert_operator BERLIN.sun.path(MIDWINTER).length, :<, BERLIN.sun.path(MIDSUMMER).length
  end

  test "draws no path on a date the sun never rose" do
    assert_empty LONGYEARBYEN.sun.path(MIDWINTER)
  end

  test "knows where it stands only with coordinates" do
    assert_predicate BERLIN.sun, :known?
    refute_predicate NOWHERE.sun, :known?
  end

  test "places nothing without coordinates" do
    assert_nil NOWHERE.sun.position(Time.utc(2026, 6, 21, 10))
    assert_nil NOWHERE.sun.sunrise(MIDSUMMER)
    assert_nil NOWHERE.sun.sunset(MIDSUMMER)
    assert_empty NOWHERE.sun.path(MIDSUMMER)
  end

  test "calls every hour day without coordinates, because an icon has to pick one" do
    assert NOWHERE.sun.daytime?(Time.utc(2026, 6, 21, 0))
  end

  test "answers exactly false for known?, not merely a falsy nil" do
    assert_equal false, NOWHERE.sun.known?
  end

  test "converts sunrise and sunset into the location's own zone, not the app default" do
    sunrise = TOKYO.sun.sunrise(MIDSUMMER)

    assert_equal "Asia/Tokyo", sunrise.time_zone.name
  end

  test "anchors the path to the location's own midnight, not the app's default zone" do
    local_noon = ActiveSupport::TimeZone["Asia/Tokyo"].local(2026, 6, 21, 12)
    expected = TOKYO.sun.position(local_noon)

    actual = TOKYO.sun.path(MIDSUMMER).find { |waypoint| waypoint.hour == 12.0 }

    assert_in_delta expected.azimuth, actual.azimuth, 0.01
    assert_in_delta expected.elevation, actual.elevation, 0.01
  end

  test "samples the whole day from local midnight up to but excluding the next one" do
    hours = LONGYEARBYEN.sun.path(MIDSUMMER).map(&:hour)

    assert_equal 96, hours.length
    assert_equal 0.0, hours.first
    assert_equal 23.75, hours.last
  end
end
