require "test_helper"

class Shading::PanelCurvesTest < ActiveSupport::TestCase
  cover "Shading::PanelCurves*"

  def hour(clock, panels, date: Date.new(2026, 9, 1))
    Shading::Hour.new(
      time: Time.zone.local(date.year, date.month, date.day, clock),
      pv_w: panels.compact.sum,
      irradiance_w_per_m2: 500.0,
      panels: panels,
      azimuth: 180.0,
      elevation: 30.0
    )
  end

  def build(hours) = Shading::PanelCurves.new.build(hours)

  test "averages each panel over the clock hours of the counted days" do
    hours = [
      hour(11, [ 100.0, 200.0, 300.0, 400.0 ]),
      hour(11, [ 300.0, 200.0, 300.0, 400.0 ], date: Date.new(2026, 9, 2)),
      hour(12, [ 500.0, 600.0, 700.0, 800.0 ])
    ]

    panels = build(hours)

    assert_equal [ [ 11, 200.0 ], [ 12, 500.0 ] ], panels.curve(:pv1).points
    assert_equal [ [ 11, 200.0 ], [ 12, 600.0 ] ], panels.curve(:pv2).points
    assert_equal 2, panels.days
    assert_equal Date.new(2026, 9, 1), panels.since
  end

  test "drops the days on which a panel never delivered" do
    silent = hour(12, [ 500.0, 600.0, 0.0, 0.0 ], date: Date.new(2026, 8, 1))
    full = hour(12, [ 100.0, 100.0, 100.0, 100.0 ])

    panels = build([ silent, full ])

    assert_equal [ [ 12, 100.0 ] ], panels.curve(:pv1).points
    assert_equal 1, panels.days
    assert_equal Date.new(2026, 9, 1), panels.since
  end

  test "keeps a day on which a panel rested only for an hour" do
    morning = hour(8, [ 50.0, 50.0, 0.0, 0.0 ])
    noon = hour(12, [ 400.0, 400.0, 400.0, 400.0 ])

    assert_equal 1, build([ morning, noon ]).days
    assert_equal [ [ 8, 0.0 ], [ 12, 400.0 ] ], build([ morning, noon ]).curve(:pv3).points
  end

  test "skips the hours the inverter reported no panel for" do
    assert build([ hour(12, [ nil, nil, nil, nil ]) ]).empty?
    assert build([ hour(12, [ 100.0, 100.0, 100.0, nil ]) ]).empty?
  end

  test "is empty without hours" do
    panels = build([])

    assert panels.empty?
    assert_equal 0, panels.days
    assert_nil panels.since
  end

  test "cuts the night off the panels' day" do
    night = hour(2, [ 0.0, 0.0, 0.0, 0.0 ])
    noon = hour(12, [ 400.0, 400.0, 400.0, 400.0 ])

    assert_equal [ 12 ], build([ night, noon ]).curve(:pv1).points.map(&:first)
  end
end
