require "test_helper"

class SolakonReadingTest < ActiveSupport::TestCase
  test "validates required fields" do
    reading = SolakonReading.new

    assert_not reading.valid?
    assert_includes reading.errors[:taken_at], "can't be blank"
    assert_includes reading.errors[:active_power_w], "can't be blank"
    assert_includes reading.errors[:pv_power_w], "can't be blank"
    assert_includes reading.errors[:battery_power_w], "can't be blank"
    assert_includes reading.errors[:battery_soc_pct], "can't be blank"
  end

  test "latest_fresh returns newest reading inside stale threshold" do
    old = SolakonReading.create!(
      taken_at: 5.minutes.ago,
      active_power_w: 100,
      pv_power_w: 120,
      battery_power_w: 0,
      battery_soc_pct: 80
    )
    fresh = SolakonReading.create!(
      taken_at: 10.seconds.ago,
      active_power_w: 220,
      pv_power_w: 260,
      battery_power_w: -40,
      battery_soc_pct: 81
    )

    assert_equal fresh, SolakonReading.latest_fresh(stale_after_s: 120, now: Time.current)
    travel 3.minutes do
      assert_nil SolakonReading.latest_fresh(stale_after_s: 120, now: Time.current)
    end
  end

  test "battery_display_power_w is positive while charging and negative while discharging" do
    charging = SolakonReading.new(battery_power_w: -50)
    discharging = SolakonReading.new(battery_power_w: 50)

    assert_equal 50, charging.battery_display_power_w
    assert_equal(-50, discharging.battery_display_power_w)
  end
end
