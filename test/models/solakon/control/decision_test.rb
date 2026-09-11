require "test_helper"

class ControlDecisionTest < ActiveSupport::TestCase
  cover "Solakon::Control::Decision*"

  test "a decision carries the mode, the target and the trim flag" do
    decision = Solakon::Control::Decision.new(state: :surplus, target_w: 485, trim: false)

    assert_equal :surplus, decision.state
    assert_equal 485, decision.target_w
    assert_equal false, decision.trim
  end

  test "an unknown mode is rejected" do
    assert_raises(Dry::Struct::Error) do
      Solakon::Control::Decision.new(state: :cruising, target_w: 100, trim: false)
    end
  end

  test "no target has been written yet before the first tick" do
    assert_nil Solakon::Control::Decision.new(state: :normal, target_w: nil, trim: false).target_w
  end

  test "two decisions with the same content are the same decision" do
    assert_equal Solakon::Control::Decision.new(state: :probe, target_w: 150, trim: true),
                 Solakon::Control::Decision.new(state: :probe, target_w: 150, trim: true)
  end
end
