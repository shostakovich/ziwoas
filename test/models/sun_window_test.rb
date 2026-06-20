require "test_helper"

class SunWindowTest < ActiveSupport::TestCase
  setup { @tz = Time.zone; Time.zone = "Europe/Berlin" }
  teardown { Time.zone = @tz }

  test "without weather it falls back to 06:00 and 20:00" do
    midday = Time.zone.local(2026, 6, 20, 12, 0, 0)
    win = SunWindow.for(now: midday, weather: nil, timezone: "Europe/Berlin")
    assert win.daytime?

    night = Time.zone.local(2026, 6, 20, 22, 0, 0)
    win2 = SunWindow.for(now: night, weather: nil, timezone: "Europe/Berlin")
    assert_not win2.daytime?
  end

  test "hours_until_sunrise uses tomorrow's sunrise late at night" do
    night = Time.zone.local(2026, 6, 20, 22, 0, 0) # after 06:00 fallback sunrise
    win = SunWindow.for(now: night, weather: nil, timezone: "Europe/Berlin")
    # next sunrise is 06:00 on the 21st => 8 hours away, never 0
    assert_in_delta 8.0, win.hours_until_sunrise, 0.001
  end

  test "hours_until_sunrise uses today's sunrise in the early morning" do
    early = Time.zone.local(2026, 6, 20, 3, 0, 0) # before 06:00 fallback sunrise
    win = SunWindow.for(now: early, weather: nil, timezone: "Europe/Berlin")
    assert_in_delta 3.0, win.hours_until_sunrise, 0.001
  end
end
