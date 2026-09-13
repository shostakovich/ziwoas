require "test_helper"

class LocationTest < ActiveSupport::TestCase
  cover "Location*"

  test "parses the zone once and hands it out as an object" do
    zone = Location.new(timezone: "Europe/Berlin").timezone

    assert_kind_of ActiveSupport::TimeZone, zone
    assert_equal "Europe/Berlin", zone.name
  end

  test "names its zone for the interfaces that insist on a string" do
    assert_equal "Pacific/Honolulu", Location.new(timezone: "Pacific/Honolulu").timezone_name
  end

  test "refuses a zone no clock runs in" do
    error = assert_raises(ArgumentError) { Location.new(timezone: "Not/AZone") }

    assert_match(/Not\/AZone/, error.message)
  end

  test "is located once both coordinates are there" do
    assert_predicate Location.new(timezone: "UTC", lat: 52.52, lon: 13.405), :located?
  end

  test "is not located while a coordinate is missing" do
    refute_predicate Location.new(timezone: "UTC"), :located?
    refute_predicate Location.new(timezone: "UTC", lat: 52.52), :located?
    refute_predicate Location.new(timezone: "UTC", lon: 13.405), :located?
  end

  test "keeps the coordinates it was given" do
    location = Location.new(timezone: "UTC", lat: 52.52, lon: 13.405)

    assert_in_delta 52.52, location.lat
    assert_in_delta 13.405, location.lon
  end

  test "picks the sun that can compute once it knows where it stands" do
    assert_instance_of Sun::Located, Location.new(timezone: "UTC", lat: 52.52, lon: 13.405).sun
  end

  test "picks the sun that knows nothing while it has no coordinates" do
    assert_instance_of Sun::Unknown, Location.new(timezone: "UTC").sun
  end

  test "keeps one sun rather than a new one per question" do
    location = Location.new(timezone: "UTC", lat: 52.52, lon: 13.405)

    assert_same location.sun, location.sun
  end

  test "gives the located sun the location itself, so it can read real coordinates" do
    location = Location.new(timezone: "UTC", lat: 52.52, lon: 13.405)

    assert_kind_of Sun::Position, location.sun.position(Time.utc(2026, 6, 21, 12))
  end
end
