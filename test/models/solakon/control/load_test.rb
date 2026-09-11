require "test_helper"

class ControlLoadTest < ActiveSupport::TestCase
  cover "Solakon::Control::Load*"

  test "effective_w uses live consumption" do
    estimate = Solakon::Control::Load.new(current_w: 800.0, floor_w: 85.0)

    assert_in_delta 800.0, estimate.effective_w, 0.001
  end

  test "effective_w falls back to floor when live load is unavailable" do
    estimate = Solakon::Control::Load.new(current_w: nil, floor_w: 85.0)

    assert_in_delta 85.0, estimate.effective_w, 0.001
  end

  # No fresh measurement is nil, never 0 W — the distinction is the whole point
  # of the guaranteed floor.
  test "an absent live measurement stays absent" do
    assert_nil Solakon::Control::Load.new(current_w: nil, floor_w: 85.0).current_w
  end

  test "watts arrive as watts however they were counted" do
    estimate = Solakon::Control::Load.new(current_w: 800, floor_w: "85")

    assert_in_delta 800.0, estimate.current_w, 0.001
    assert_in_delta 85.0, estimate.floor_w, 0.001
  end
end
