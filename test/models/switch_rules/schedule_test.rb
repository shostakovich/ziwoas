require "test_helper"

class SwitchRules::ScheduleTest < ActiveSupport::TestCase
  # Plain structs, no Active Record: the folding is pure Ruby and the test says so.
  Rule = Struct.new(:id, :action, :at_minute, :days, :enabled, :group_id, keyword_init: true)

  def rule(**overrides)
    Rule.new({ id: 1, action: "on", at_minute: 600, days: [ 1 ], enabled: true, group_id: nil }.merge(overrides))
  end

  def fold(rules) = SwitchRules::Schedule.fold(rules)

  # --- folding ----------------------------------------------------------

  test "two rules of one group fold into a window" do
    on  = rule(id: 1, action: "on",  at_minute: 600,  group_id: "g")
    off = rule(id: 2, action: "off", at_minute: 1200, group_id: "g")

    entries = fold([ on, off ])

    assert_equal 1, entries.size
    assert_instance_of SwitchRules::Schedule::Window, entries.first
    assert_equal on,  entries.first.on
    assert_equal off, entries.first.off
    assert_equal "g", entries.first.id
  end

  test "a window finds its halves regardless of the order they arrive in" do
    on  = rule(id: 2, action: "on",  at_minute: 600,  group_id: "g")
    off = rule(id: 1, action: "off", at_minute: 1200, group_id: "g")

    window = fold([ off, on ]).first

    assert_equal on,  window.on
    assert_equal off, window.off
  end

  test "a rule without a group folds into a single, keeping its direction" do
    entries = fold([ rule(id: 7, action: "off", at_minute: 1320) ])

    assert_equal 1, entries.size
    assert_instance_of SwitchRules::Schedule::Single, entries.first
    assert_equal "off", entries.first.action
    assert_equal 7,     entries.first.id
  end

  test "groups are folded independently of each other" do
    entries = fold([
      rule(id: 1, action: "on",  at_minute: 360,  group_id: "a"),
      rule(id: 2, action: "off", at_minute: 600,  group_id: "a"),
      rule(id: 3, action: "on",  at_minute: 900,  group_id: "b"),
      rule(id: 4, action: "off", at_minute: 1200, group_id: "b"),
      rule(id: 5, action: "off", at_minute: 1380)
    ])

    assert_equal [ "a", "b", 5 ], entries.map(&:id)
  end

  test "an empty list folds into no entries" do
    assert_empty fold([])
  end

  # --- what an entry exposes --------------------------------------------

  test "a window carries the weekdays, time and pause state of its group" do
    window = fold([
      rule(id: 1, action: "on",  at_minute: 600,  days: [ 1, 2 ], enabled: false, group_id: "g"),
      rule(id: 2, action: "off", at_minute: 1200, days: [ 1, 2 ], enabled: false, group_id: "g")
    ]).first

    assert_equal [ 1, 2 ], window.days
    assert_equal 600,      window.at_minute
    refute window.enabled?
  end

  test "a single carries the weekdays, time and pause state of its rule" do
    single = fold([ rule(id: 1, at_minute: 1320, days: [ 6, 7 ], enabled: false) ]).first

    assert_equal [ 6, 7 ], single.days
    assert_equal 1320,     single.at_minute
    refute single.enabled?
  end

  # --- the day shift, undone --------------------------------------------

  test "a midnight crosser shows the weekdays of its on rule, not the shifted off days" do
    window = fold([
      rule(id: 1, action: "on",  at_minute: 1320, days: [ 1, 2, 3, 4, 5 ], group_id: "g"),  # Mo-Fr 22:00 an
      rule(id: 2, action: "off", at_minute: 360,  days: [ 2, 3, 4, 5, 6 ], group_id: "g")   # Di-Sa 06:00 aus
    ]).first

    assert_equal [ 1, 2, 3, 4, 5 ], window.days
    assert_equal 1320, window.at_minute
  end

  # --- sorting ----------------------------------------------------------

  test "entries sort by their earliest time, a window by its on time" do
    entries = fold([
      rule(id: 1, at_minute: 1320),
      rule(id: 2, action: "on",  at_minute: 600,  group_id: "g"),
      rule(id: 3, action: "off", at_minute: 1200, group_id: "g"),
      rule(id: 4, at_minute: 300)
    ])

    assert_equal [ 4, "g", 1 ], entries.map(&:id)
  end

  test "a midnight crosser sorts by its on time, not its earlier off time" do
    entries = fold([
      rule(id: 1, action: "on",  at_minute: 1320, group_id: "g"),
      rule(id: 2, action: "off", at_minute: 360,  group_id: "g"),
      rule(id: 3, at_minute: 600)
    ])

    assert_equal [ 3, "g" ], entries.map(&:id)
  end

  test "entries at the same time sort by their smallest rule id" do
    entries = fold([
      rule(id: 5, at_minute: 600),
      rule(id: 3, action: "on",  at_minute: 600, group_id: "g"),
      rule(id: 9, action: "off", at_minute: 900, group_id: "g"),
      rule(id: 4, at_minute: 600)
    ])

    assert_equal [ "g", 4, 5 ], entries.map(&:id)
  end

  # --- the half group ---------------------------------------------------

  test "a group missing its partner folds into a plain single" do
    entries = fold([ rule(id: 1, action: "on", at_minute: 600, group_id: "lonely") ])

    assert_instance_of SwitchRules::Schedule::Single, entries.first
    assert_equal 1, entries.first.id
  end

  test "a group pointing twice the same way folds into singles" do
    entries = fold([
      rule(id: 1, action: "on", at_minute: 600, group_id: "twice"),
      rule(id: 2, action: "on", at_minute: 900, group_id: "twice")
    ])

    assert_equal [ 1, 2 ], entries.map(&:id)
    assert entries.all? { |e| e.is_a?(SwitchRules::Schedule::Single) }
  end
end
