require "test_helper"

class SwitchRuleTest < ActiveSupport::TestCase
  def valid_attrs
    { plug_id: "fridge", action: "off", at_minute: 1320, days: [ 1, 2, 3, 4, 5 ] }
  end

  test "valid rule saves" do
    assert SwitchRule.new(valid_attrs).valid?
  end

  test "plug_id is required" do
    refute SwitchRule.new(valid_attrs.merge(plug_id: "")).valid?
  end

  test "action must be on or off" do
    assert SwitchRule.new(valid_attrs.merge(action: "on")).valid?
    refute SwitchRule.new(valid_attrs.merge(action: "toggle")).valid?
    refute SwitchRule.new(valid_attrs.merge(action: nil)).valid?
  end

  test "enabled defaults to true" do
    assert SwitchRule.create!(valid_attrs).enabled
  end

  test "group_id is optional" do
    assert_nil SwitchRule.create!(valid_attrs).group_id
  end

  test "at_minute must be within 0..1439" do
    refute SwitchRule.new(valid_attrs.merge(at_minute: -1)).valid?
    refute SwitchRule.new(valid_attrs.merge(at_minute: 1440)).valid?
    refute SwitchRule.new(valid_attrs.merge(at_minute: nil)).valid?
    assert SwitchRule.new(valid_attrs.merge(at_minute: 0)).valid?
    assert SwitchRule.new(valid_attrs.merge(at_minute: 1439)).valid?
  end

  test "days must be a non-empty list of ISO weekdays" do
    refute SwitchRule.new(valid_attrs.merge(days: [])).valid?
    refute SwitchRule.new(valid_attrs.merge(days: [ 0 ])).valid?
    refute SwitchRule.new(valid_attrs.merge(days: [ 8 ])).valid?
    refute SwitchRule.new(valid_attrs.merge(days: nil)).valid?
  end

  test "days are normalized to sorted unique integers, blanks dropped" do
    rule = SwitchRule.create!(valid_attrs.merge(days: [ "", "5", "1", "5" ]))
    assert_equal [ 1, 5 ], rule.days
  end

  test "at_minute_time formats and parses HH:MM" do
    rule = SwitchRule.new(valid_attrs)
    assert_equal "22:00", rule.at_minute_time

    rule.at_minute_time = "07:05"
    assert_equal 425, rule.at_minute

    rule.at_minute_time = "18:00:00"
    assert_equal 1080, rule.at_minute

    rule.at_minute_time = ""
    assert_nil rule.at_minute
    assert_nil rule.at_minute_time

    rule.at_minute_time = "24:00"
    assert_nil rule.at_minute

    rule.at_minute_time = "23:60"
    assert_nil rule.at_minute
  end

  test "enabled scope" do
    SwitchRule.create!(valid_attrs)
    SwitchRule.create!(valid_attrs.merge(enabled: false))
    assert_equal 1, SwitchRule.enabled.count
  end

  test "a group holds at most one rule per direction" do
    group = SecureRandom.uuid
    SwitchRule.create!(valid_attrs.merge(group_id: group, action: "on"))
    SwitchRule.create!(valid_attrs.merge(group_id: group, action: "off"))

    assert_raises(ActiveRecord::RecordNotUnique) do
      SwitchRule.create!(valid_attrs.merge(group_id: group, action: "on"))
    end
  end

  test "groupless rules do not collide" do
    SwitchRule.create!(valid_attrs)
    assert SwitchRule.create!(valid_attrs)
  end
end
