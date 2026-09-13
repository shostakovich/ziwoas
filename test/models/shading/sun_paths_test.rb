require "test_helper"

class Shading::SunPathsTest < ActiveSupport::TestCase
  cover "Shading::SunPaths*"

  LAT = 52.52
  LON = 13.405

  def paths(lat: LAT, lon: LON, year: 2026)
    Shading::SunPaths.new(zone: "Europe/Berlin", lat: lat, lon: lon).build(year)
  end

  test "draws the solstices and the equinox" do
    assert_equal [ "21.6.", "21.3. / 23.9.", "21.12." ], paths.map(&:label)
  end

  test "climbs highest at midsummer and stays low at midwinter" do
    summer, equinox, winter = paths.map { |path| path.points.map(&:last).max }

    assert_in_delta 61.0, summer, 1.0
    assert_in_delta 37.5, equinox, 1.0
    assert_in_delta 14.0, winter, 1.0
  end

  test "keeps the sun above the horizon and moves it from east to west" do
    points = paths.first.points

    assert points.all? { |_azimuth, elevation| elevation > 0 }
    assert_equal points.map(&:first), points.map(&:first).sort
  end

  test "marks every third hour that the sun is up" do
    summer, _equinox, winter = paths

    assert_equal [ 6, 9, 12, 15, 18 ], summer.dots.map(&:hour)
    assert_equal [ 9, 12, 15 ], winter.dots.map(&:hour)
  end

  test "places the dots on the path" do
    dot = paths.first.dots.find { |candidate| candidate.hour == 12 }

    assert_in_delta 149.6, dot.azimuth, 1.0
    assert_in_delta 58.0, dot.elevation, 2.0
  end

  test "draws nothing without a location" do
    assert_empty paths(lat: nil)
    assert_empty paths(lon: nil)
  end
end
