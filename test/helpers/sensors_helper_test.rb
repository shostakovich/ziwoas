require "test_helper"

class SensorsHelperTest < ActionView::TestCase
  include SensorsHelper

  test "battery_low? returns true at or below 20" do
    assert battery_low?(19)
    assert battery_low?(20)
    refute battery_low?(21)
    refute battery_low?(nil)
  end
end
