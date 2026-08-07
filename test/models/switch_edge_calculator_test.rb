require "test_helper"

class SwitchEdgeCalculatorTest < ActiveSupport::TestCase
  # Pure unit tests: rules are plain structs, no DB.
  R = Struct.new(:id, :plug_id, :action, :at_minute, :days, keyword_init: true)

  def tz = Time.zone

  def calc(*rules)
    SwitchEdgeCalculator.new(rules: rules)
  end

  def rule(plug_id: "lamp", action: :on, at_minute: 1080, days: [ 1 ], id: nil)
    R.new(id: id, plug_id: plug_id, action: action, at_minute: at_minute, days: days)
  end

  # A Zeitfenster is now two rules; days are absolute, so a caller that wants
  # one crossing midnight puts the off rule on the following weekdays itself.
  def window(plug_id: "lamp", on_at: 1080, off_at: 1380, days: [ 1 ], off_days: nil)
    [ rule(plug_id: plug_id, action: :on,  at_minute: on_at,  days: days),
      rule(plug_id: plug_id, action: :off, at_minute: off_at, days: off_days || days) ]
  end

  test "fires on and off edges on configured weekdays" do
    c = calc(*window(on_at: 1080, off_at: 1380, days: [ 1 ]))  # Mo 18:00-23:00
    edges = c.edges_between(tz.local(2026, 6, 15, 0, 0), tz.local(2026, 6, 16, 0, 0))
    assert_equal 2, edges.length
    assert_equal [ :on, :off ], edges.map(&:action)
    assert_equal tz.local(2026, 6, 15, 18, 0), edges.first.at
    assert_equal tz.local(2026, 6, 15, 23, 0), edges.last.at
    assert_equal "lamp", edges.first.plug_id
  end

  test "skips days not in the weekday list" do
    c = calc(*window(days: [ 2 ]))  # Di only
    edges = c.edges_between(tz.local(2026, 6, 15, 0, 0), tz.local(2026, 6, 16, 0, 0))
    assert_empty edges
  end

  test "a single rule fires exactly one edge" do
    c = calc(rule(action: :off, at_minute: 1320, days: [ 1 ]))  # Mo 22:00 aus
    edges = c.edges_between(tz.local(2026, 6, 15, 0, 0), tz.local(2026, 6, 17, 0, 0))
    assert_equal 1, edges.length
    assert_equal :off, edges.first.action
    assert_equal tz.local(2026, 6, 15, 22, 0), edges.first.at
  end

  test "a window across midnight is two rules on different weekdays" do
    # Mo 22:00 an, Di 06:00 aus — the day shift lives in the stored weekdays.
    c = calc(*window(on_at: 1320, off_at: 360, days: [ 1 ], off_days: [ 2 ]))
    edges = c.edges_between(tz.local(2026, 6, 15, 0, 0), tz.local(2026, 6, 17, 0, 0))
    assert_equal tz.local(2026, 6, 15, 22, 0), edges.first.at
    assert_equal tz.local(2026, 6, 16, 6, 0),  edges.last.at
  end

  test "edges carry the id of the rule that produced them" do
    c = calc(rule(id: 42, action: :on, at_minute: 1080, days: [ 1 ]))
    edge = c.edges_between(tz.local(2026, 6, 15, 0, 0), tz.local(2026, 6, 16, 0, 0)).sole
    assert_equal 42, edge.rule_id
  end

  test "interval is exclusive at from, inclusive at to" do
    c = calc(*window)
    on_time = tz.local(2026, 6, 15, 18, 0)
    assert_empty c.edges_between(on_time, tz.local(2026, 6, 15, 18, 30))
    edges = c.edges_between(tz.local(2026, 6, 15, 17, 0), on_time)
    assert_equal [ on_time ], edges.map(&:at)
  end

  test "empty or inverted interval returns no edges" do
    c = calc(*window)
    t = tz.local(2026, 6, 15, 12, 0)
    assert_empty c.edges_between(t, t)
    assert_empty c.edges_between(t, t - 1.hour)
  end

  test "latest_edge_per_plug collapses to the most recent edge per plug" do
    c = calc(
      *window(plug_id: "lamp", on_at: 1080, off_at: 1140),  # Mo 18:00-19:00
      *window(plug_id: "fan",  on_at: 1100, off_at: 1380)   # Mo 18:20-23:00
    )
    edges = c.latest_edge_per_plug(tz.local(2026, 6, 15, 17, 0), tz.local(2026, 6, 15, 20, 0))
    assert_equal 2, edges.length
    lamp = edges.find { |e| e.plug_id == "lamp" }
    fan  = edges.find { |e| e.plug_id == "fan" }
    assert_equal :off, lamp.action  # 19:00 beats 18:00
    assert_equal :on,  fan.action   # only 18:20 inside (off is 23:00, outside)
  end

  test "on edge wins a same-timestamp tie in latest_edge_per_plug" do
    c = calc(
      *window(on_at: 1080, off_at: 1140),  # Mo 18:00-19:00
      *window(on_at: 1140, off_at: 1200)   # Mo 19:00-20:00
    )
    edges = c.latest_edge_per_plug(tz.local(2026, 6, 15, 17, 0), tz.local(2026, 6, 15, 19, 0))
    assert_equal 1, edges.length
    assert_equal :on, edges.first.action
    # And edges_between orders :off before :on at the same instant
    all = c.edges_between(tz.local(2026, 6, 15, 17, 0), tz.local(2026, 6, 15, 19, 0))
    assert_equal [ :on, :off, :on ], all.map(&:action)
  end

  test "next_edge_per_plug collapses to the earliest edge per plug" do
    c = calc(
      *window(plug_id: "lamp", on_at: 1080, off_at: 1140),  # Mo 18:00-19:00
      *window(plug_id: "fan",  on_at: 1100, off_at: 1380)   # Mo 18:20-23:00
    )
    edges = c.next_edge_per_plug(tz.local(2026, 6, 15, 17, 0), tz.local(2026, 6, 15, 20, 0))
    assert_equal 2, edges.length
    lamp = edges.find { |e| e.plug_id == "lamp" }
    fan  = edges.find { |e| e.plug_id == "fan" }
    assert_equal :on, lamp.action  # 18:00 beats 19:00
    assert_equal tz.local(2026, 6, 15, 18, 0), lamp.at
    assert_equal :on, fan.action
    assert_equal tz.local(2026, 6, 15, 18, 20), fan.at
  end

  test "on edge wins a same-timestamp tie in next_edge_per_plug" do
    c = calc(
      *window(on_at: 360, off_at: 600),  # Mo 06:00-10:00
      *window(on_at: 600, off_at: 840)   # Mo 10:00-14:00
    )
    edges = c.next_edge_per_plug(tz.local(2026, 6, 15, 9, 0), tz.local(2026, 6, 15, 20, 0))
    assert_equal 1, edges.length
    assert_equal :on, edges.first.action
    assert_equal tz.local(2026, 6, 15, 10, 0), edges.first.at
  end

  test "string actions from the database become symbols on the edge" do
    c = calc(R.new(id: 1, plug_id: "lamp", action: "off", at_minute: 1320, days: [ 1 ]))
    edge = c.edges_between(tz.local(2026, 6, 15, 0, 0), tz.local(2026, 6, 16, 0, 0)).sole
    assert_equal :off, edge.action
  end

  test "fall-back repetition fires the edge only once" do
    # 2026-10-25 (Sunday) 03:00 -> 02:00 in Europe/Berlin; 02:30 happens twice.
    # The plug must not switch on both times — the earlier one wins.
    c = calc(rule(action: :on, at_minute: 150, days: [ 7 ]))  # So 02:30 an
    edges = c.edges_between(tz.local(2026, 10, 25, 0, 0), tz.local(2026, 10, 25, 12, 0))
    assert_equal 1, edges.length
    assert_equal 7200, edges.sole.at.utc_offset  # CEST, i.e. the first pass
  end

  test "spring-forward gap shifts the edge forward" do
    # 2026-03-29 (Sunday) 02:00 -> 03:00 in Europe/Berlin; 02:30 does not exist.
    c = calc(*window(on_at: 150, off_at: 240, days: [ 7 ]))  # So 02:30-04:00
    edges = c.edges_between(tz.local(2026, 3, 29, 0, 0), tz.local(2026, 3, 29, 12, 0))
    assert_equal 2, edges.length
    assert_equal 3, edges.first.at.hour
    assert_equal 30, edges.first.at.min
  end
end
