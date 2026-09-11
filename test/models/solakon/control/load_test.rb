require "test_helper"

class ControlLoadTest < ActiveSupport::TestCase
  cover "Solakon::Control::Load#effective_w"

  test "effective_w uses live consumption" do
    estimate = Solakon::Control::Load.new(current_w: 800.0, floor_w: 85.0)

    assert_in_delta 800.0, estimate.effective_w, 0.001
  end

  test "effective_w falls back to floor when live load is unavailable" do
    estimate = Solakon::Control::Load.new(current_w: nil, floor_w: 85.0)

    assert_in_delta 85.0, estimate.effective_w, 0.001
  end
end
