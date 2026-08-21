require "test_helper"

class Switching::Rules::SaveWindowTest < ActiveSupport::TestCase
  setup { Switching::Rule.delete_all }

  def save(on: "10:00", off: "20:00", days: [ 1, 2, 3, 4, 5 ], group_id: nil)
    Switching::Rules::SaveWindow.call(
      plug_id: "fridge",
      attrs:   { on_at_time: on, off_at_time: off, days: days },
      group_id: group_id
    )
  end

  def rules_of(group_id) = Switching::Rule.where(group_id: group_id).order(:action)

  test "writes exactly two rules of one group, one per direction" do
    group_id = save

    off, on = rules_of(group_id).to_a
    assert_equal 2, Switching::Rule.count
    assert_equal [ "fridge", "on",  600,  [ 1, 2, 3, 4, 5 ], true, group_id ],
                 [ on.plug_id, on.action, on.at_minute, on.days, on.enabled, on.group_id ]
    assert_equal [ "fridge", "off", 1200, [ 1, 2, 3, 4, 5 ], true, group_id ],
                 [ off.plug_id, off.action, off.at_minute, off.days, off.enabled, off.group_id ]
  end

  test "two windows get two groups" do
    refute_equal save, save(on: "06:00", off: "08:00")
    assert_equal 2, Switching::Rule.where(action: "on").count
  end

  test "an off time before the on time shifts the off weekdays one day forward" do
    group_id = save(on: "22:00", off: "06:00", days: [ 1, 2, 3, 4, 5 ])

    off, on = rules_of(group_id).to_a
    assert_equal [ 1, 2, 3, 4, 5 ], on.days
    assert_equal [ 2, 3, 4, 5, 6 ], off.days
  end

  test "the day shift wraps Sunday around to Monday" do
    group_id = save(on: "22:00", off: "06:00", days: [ 6, 7 ])

    assert_equal [ 1, 7 ], rules_of(group_id).find_by(action: "off").days
  end

  test "editing updates both rules in place, keeping their ids" do
    group_id = save
    before   = rules_of(group_id).pluck(:id)

    save(on: "11:00", off: "21:00", days: [ 6 ], group_id: group_id)

    off, on = rules_of(group_id).to_a
    assert_equal before, rules_of(group_id).pluck(:id)
    assert_equal [ 660, [ 6 ] ], [ on.at_minute, on.days ]
    assert_equal [ 1260, [ 6 ] ], [ off.at_minute, off.days ]
    assert_equal 2, Switching::Rule.count
  end

  test "editing a paused window leaves it paused" do
    group_id = save
    Switching::Rule.where(group_id: group_id).update_all(enabled: false)

    save(on: "11:00", off: "21:00", group_id: group_id)

    assert_equal [ false, false ], rules_of(group_id).pluck(:enabled)
  end

  test "a rejected half rolls the whole window back" do
    assert_raises(ActiveRecord::RecordInvalid) { save(off: "24:00") }
    assert_equal 0, Switching::Rule.count
  end
end
