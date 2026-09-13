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
      hour(azimuth: 141.0, elevation: 46.0, pv_w: 700.0),
      hour(azimuth: 142.0, elevation: 47.0, pv_w: 100.0),
      hour(azimuth: 143.0, elevation: 48.0, pv_w: 400.0)
    ]

    bin = build(hours, best_ratio: 1.0).bins.sole

    assert_in_delta 0.8, bin.share, 0.001
    assert_equal 3, bin.hours
  end

  test "averages the two middle hours of an even field" do
    hours = [ 600.0, 100.0, 200.0, 300.0 ].map { |watts| hour(azimuth: 141.0, elevation: 46.0, pv_w: watts) }

    assert_in_delta 0.5, build(hours, best_ratio: 1.0).bins.sole.share, 0.001
  end

  test "finds the middle of a larger even field" do
    watts = [ 600.0, 500.0, 100.0, 200.0, 300.0, 400.0 ]
    hours = watts.map { |pv_w| hour(azimuth: 141.0, elevation: 46.0, pv_w: pv_w) }

    assert_in_delta 0.7, build(hours, best_ratio: 1.0).bins.sole.share, 0.001
  end

  test "reads the median against the best hour ever seen" do
    hours = [ hour(azimuth: 100.0, elevation: 20.0) ] * 3

    assert_in_delta 0.4, build(hours, best_ratio: 2.0).bins.sole.share, 0.001
  end

  test "draws no field before a best hour is known" do
    hours = [ hour(azimuth: 100.0, elevation: 20.0) ] * 3

    assert_equal [], build(hours, best_ratio: nil).bins
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

  test "keeps hours the station measured at exactly the threshold" do
    hours = [ hour(azimuth: 100.0, elevation: 20.0, irradiance: 100.0) ] * 3

    assert_equal 3, build(hours).bins.sole.hours
  end

  test "keeps hours with the sun just above the horizon" do
    hours = [ hour(azimuth: 100.0, elevation: 0.5) ] * 3

    assert_equal [ [ 100, 0 ] ], build(hours).bins.map { |bin| [ bin.azimuth, bin.elevation ] }
  end

  test "skips hours whose sun position was never known" do
    assert_empty build([ hour(azimuth: nil, elevation: nil) ] * 3).bins
  end

  test "names the hours of the day a field was measured in" do
    hours = [ 9, 7, 10, 8 ].map { |clock| hour(azimuth: 100.0, elevation: 20.0, clock: clock) }

    bin = build(hours).bins.sole

    assert_equal 7, bin.first_hour
    assert_equal 10, bin.last_hour
  end

  test "carries the sun paths it is drawn under" do
    paths = [ Shading::Path.new(label: "21.6.", points: [], dots: []) ]

    assert_equal paths, build([], paths: paths).paths
  end
end
