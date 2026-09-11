require "test_helper"

class LoadEstimateTest < ActiveSupport::TestCase
  cover "LoadEstimate#effective_w"

  test "effective_w uses live consumption" do
    estimate = LoadEstimate.new(current_w: 800.0, floor_w: 85.0)

    assert_in_delta 800.0, estimate.effective_w, 0.001
  end

  test "effective_w falls back to floor when live load is unavailable" do
    estimate = LoadEstimate.new(current_w: nil, floor_w: 85.0)

    assert_in_delta 85.0, estimate.effective_w, 0.001
  end
end
