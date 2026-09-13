require "test_helper"

class Shading::YieldMapTest < ActiveSupport::TestCase
  cover "Shading::YieldMap*"

  def hour(azimuth:, elevation:, pv_w: 400.0, irradiance: 500.0, clock: 12)
    Shading::Hour.new(
      time: Time.zone.local(2026, 7, 1, clock),
      pv_w: pv_w,
      irradiance_w_per_m2: irradiance,
      panels: [],
      azimuth: azimuth,
      elevation: elevation
    )
  end

  def build(hours, best_ratio: 1.0, paths: [])
    Shading::YieldMap.new(best_ratio: best_ratio).build(hours, paths)
  end

  test "puts an hour into the field of five degrees it fell into" do
    map = build([ hour(azimuth: 143.2, elevation: 47.9) ] * 3)

    assert_equal 5, map.bin_size
    assert_equal [ [ 140, 45 ] ], map.bins.map { |bin| [ bin.azimuth, bin.elevation ] }
  end

  test "takes the median of the hours in a field, as a share of the best hour" do
    hours = [
      hour(azimuth: 141.0, elevation: 46.0, pv_w: 100.0),
      hour(azimuth: 142.0, elevation: 47.0, pv_w: 400.0),
      hour(azimuth: 143.0, elevation: 48.0, pv_w: 700.0)
    ]

    bin = build(hours, best_ratio: 1.0).bins.sole

    assert_in_delta 0.8, bin.share, 0.001
    assert_equal 3, bin.hours
  end

  test "averages the two middle hours of an even field" do
    hours = [ 100.0, 200.0, 300.0, 600.0 ].map { |watts| hour(azimuth: 141.0, elevation: 46.0, pv_w: watts) }

    assert_in_delta 0.5, build(hours, best_ratio: 1.0).bins.sole.share, 0.001
  end

  test "leaves a field with fewer than three hours empty" do
    assert_empty build([ hour(azimuth: 100.0, elevation: 20.0) ] * 2).bins
  end

  test "skips hours the station barely measured, and the sun below the horizon" do
    dim = [ hour(azimuth: 100.0, elevation: 20.0, irradiance: 99.9) ] * 3
    night = [ hour(azimuth: 100.0, elevation: -0.5, irradiance: 500.0) ] * 3

    assert_empty build(dim + night).bins
  end

  test "skips hours the station left unmeasured" do
    assert_empty build([ hour(azimuth: 100.0, elevation: 20.0, irradiance: nil) ] * 3).bins
  end

  test "names the hours of the day a field was measured in" do
    hours = [ hour(azimuth: 100.0, elevation: 20.0, clock: 9), hour(azimuth: 100.0, elevation: 20.0, clock: 7),
              hour(azimuth: 100.0, elevation: 20.0, clock: 8) ]

    bin = build(hours).bins.sole

    assert_equal 7, bin.first_hour
    assert_equal 9, bin.last_hour
  end

  test "carries the sun paths it is drawn under" do
    paths = [ Shading::Path.new(label: "21.6.", points: [], dots: []) ]

    assert_equal paths, build([], paths: paths).paths
  end
end
