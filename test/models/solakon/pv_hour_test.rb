require "test_helper"

class SolakonPvHourTest < ActiveSupport::TestCase
  cover "Solakon::PvHour*"

  test "requires the hour, its mean PV power and the reading count" do
    hour = Solakon::PvHour.new

    assert_not hour.valid?
    assert_includes hour.errors[:started_at], "can't be blank"
    assert_includes hour.errors[:pv_power_w], "can't be blank"
    assert_includes hour.errors[:reading_count], "can't be blank"
  end
end
