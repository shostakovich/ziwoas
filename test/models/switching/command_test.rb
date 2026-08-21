require "test_helper"

class SwitchCommandTest < ActiveSupport::TestCase
  setup { Switching::Command.delete_all }

  test "validates action and source" do
    refute Switching::Command.new(plug_id: "x", action: "toggle", source: "manual").valid?
    refute Switching::Command.new(plug_id: "x", action: "on", source: "api").valid?
    assert Switching::Command.new(plug_id: "x", action: "on", source: "schedule").valid?
  end

  test "latest_for returns newest command for plug" do
    Switching::Command.create!(plug_id: "a", action: "on",  source: "manual",   created_at: 2.hours.ago)
    Switching::Command.create!(plug_id: "a", action: "off", source: "schedule", created_at: 1.hour.ago)
    Switching::Command.create!(plug_id: "b", action: "on",  source: "manual",   created_at: 1.minute.ago)
    assert_equal "off", Switching::Command.latest_for("a").action
    assert_nil Switching::Command.latest_for("missing")
  end

  test "manual_after? only counts manual commands after the given time" do
    Switching::Command.create!(plug_id: "a", action: "on", source: "schedule", created_at: 1.minute.ago)
    refute Switching::Command.manual_after?("a", 5.minutes.ago)
    Switching::Command.create!(plug_id: "a", action: "off", source: "manual", created_at: 1.minute.ago)
    assert Switching::Command.manual_after?("a", 5.minutes.ago)
    refute Switching::Command.manual_after?("a", Time.current)
  end
end
