require "test_helper"

class Shading::DailyProfilesTest < ActiveSupport::TestCase
  cover "Shading::DailyProfiles*"

  def hour(clock, pv_w: 400.0, irradiance: 500.0, elevation: 30.0, date: Date.new(2026, 7, 1))
    Shading::Hour.new(
      time: Time.zone.local(date.year, date.month, date.day, clock),
      pv_w: pv_w,
      irradiance_w_per_m2: irradiance,
      panels: [],
      azimuth: 180.0,
      elevation: elevation
    )
  end

  def build(hours, best_ratio: 1.0) = Shading::DailyProfiles.new(best_ratio: best_ratio).build(hours)

  test "gives every month its own profile, in the order of the year" do
    profiles = build([ hour(12, date: Date.new(2026, 8, 3)), hour(12, date: Date.new(2026, 5, 3)) ])

    assert_equal [ 5, 8 ], profiles.map(&:month)
    assert_equal [ 1, 1 ], profiles.map(&:days)
  end

  test "averages the measured power of one clock hour over the month's days" do
    hours = [ hour(11, pv_w: 200.0), hour(11, pv_w: 400.0, date: Date.new(2026, 7, 2)), hour(12, pv_w: 900.0) ]

    profile = build(hours).sole

    assert_equal [ [ 11, 300.0 ], [ 12, 900.0 ] ], profile.curve(:measured).points
    assert_equal 2, profile.days
  end

  test "turns the irradiance into the power the array would have made of it" do
    profile = build([ hour(12, irradiance: 500.0) ], best_ratio: 0.8).sole

    assert_equal [ [ 12, 400.0 ] ], profile.curve(:expected).points
  end

  test "draws the cloudless sky from the sun's height, on the same scale" do
    profile = build([ hour(12, elevation: 90.0) ], best_ratio: 0.5).sole

    assert_in_delta 517.5, profile.curve(:theory).points.sole.last, 0.5
  end

  test "leaves the expected curve out where the station measured nothing" do
    profile = build([ hour(12, irradiance: nil) ]).sole

    assert_empty profile.curve(:expected).points
    assert_equal [ [ 12, 400.0 ] ], profile.curve(:measured).points
  end

  test "leaves the cloudless sky out where the sun position is unknown" do
    profile = build([ hour(12, elevation: nil) ]).sole

    assert_empty profile.curve(:theory).points
    assert_equal [ [ 12, 400.0 ] ], profile.curve(:measured).points
  end

  test "averages a clock hour over the days the station measured, ignoring the rest" do
    hours = [ hour(12, irradiance: nil), hour(12, irradiance: 500.0, date: Date.new(2026, 7, 2)) ]

    profile = build(hours).sole

    assert_equal [ [ 12, 500.0 ] ], profile.curve(:expected).points
  end

  test "leaves the scaled curves empty until a best hour is known" do
    profile = build([ hour(12) ], best_ratio: nil).sole

    assert_empty profile.curve(:expected).points
    assert_empty profile.curve(:theory).points
    assert_equal [ [ 12, 400.0 ] ], profile.curve(:measured).points
  end

  test "puts the clock hours of a profile in the order of the day" do
    profile = build([ hour(12), hour(10), hour(11) ]).sole

    assert_equal [ 10, 11, 12 ], profile.curve(:measured).points.map(&:first)
    assert_equal [ 10, 11, 12 ], profile.curve(:expected).points.map(&:first)
  end

  test "has no profile without hours" do
    assert_empty build([])
  end

  test "cuts the night off the day's shape" do
    night = [ hour(2, pv_w: 0.0, irradiance: 0.0, elevation: -20.0), hour(23, pv_w: 0.0, irradiance: 0.0, elevation: -20.0) ]

    profile = build([ *night, hour(12) ]).sole

    assert_equal [ 12 ], profile.curve(:measured).points.map(&:first)
    assert_equal [ 12 ], profile.curve(:theory).points.map(&:first)
  end

  test "keeps nothing of a day on which nothing was ever produced" do
    dark = [ 8, 12 ].map { |clock| hour(clock, pv_w: 0.0, irradiance: 0.0, elevation: nil) }

    profile = build(dark).sole

    assert_empty profile.curve(:measured).points
    assert_empty profile.curve(:expected).points
    assert_empty profile.curve(:theory).points
  end

  test "opens the day at the earliest and closes it at the latest hour that carried something" do
    hours = [
      hour(8, pv_w: 0.0, irradiance: 500.0, elevation: nil),
      hour(10, pv_w: 400.0, irradiance: 0.0, elevation: nil),
      hour(12, pv_w: 0.0, irradiance: 500.0, elevation: nil),
      hour(14, pv_w: 400.0, irradiance: 0.0, elevation: nil)
    ]

    profile = build(hours).sole

    assert_equal [ 8, 10, 12, 14 ], profile.curve(:measured).points.map(&:first)
  end

  test "keeps an hour of zero inside the day" do
    profile = build([ hour(10), hour(11, pv_w: 0.0), hour(12) ]).sole

    assert_equal [ 10, 11, 12 ], profile.curve(:measured).points.map(&:first)
  end

  test "counts an hour the station left out for neither of the two lines" do
    measured_only = hour(12, pv_w: 900.0, irradiance: nil, date: Date.new(2026, 7, 2))
    paired = hour(12, pv_w: 300.0, irradiance: 400.0)

    profile = build([ paired, measured_only ]).sole

    # 900 W would lift the measured line over a day the expected line never saw.
    assert_equal [ [ 12, 300.0 ] ], profile.curve(:measured).points
    assert_equal [ [ 12, 400.0 ] ], profile.curve(:expected).points
    assert_equal 1, profile.days
  end

  test "keeps the measured line of a month the station never covered" do
    profile = build([ hour(11, irradiance: nil), hour(12, pv_w: 800.0, irradiance: nil) ]).sole

    assert_equal [ [ 11, 400.0 ], [ 12, 800.0 ] ], profile.curve(:measured).points
    assert_empty profile.curve(:expected).points
    assert_equal 1, profile.days
  end
end
