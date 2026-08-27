require "test_helper"

class SolakonSnapshotTest < ActiveSupport::TestCase
  test "requires taken_at and validates numeric fields" do
    snapshot = SolakonSnapshot.new(pv1_power_w: "bright")

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:taken_at], "can't be blank"
    assert_includes snapshot.errors[:pv1_power_w], "is not a number"
  end

  test "status_messages delegates to user-facing decoder" do
    snapshot = SolakonSnapshot.new(status1: 4, status3: 0, alarm1: 0, alarm2: 8, alarm3: 0, bms_faults: [ 0, 0, 0, 0, 0, 0 ])

    assert_includes snapshot.status_messages, "Wechselrichter in Betrieb"
    assert_includes snapshot.status_messages, "Temperatur zu hoch"
    assert snapshot.status_messages.none? { |message| message.match?(/SOH|EPS|390|Alarm 2|Bit/) }
  end
end
