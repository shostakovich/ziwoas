require "test_helper"

class SolakonControlStateTest < ActiveSupport::TestCase
  setup { SolakonControlState.delete_all if defined?(SolakonControlState) }

  test "current returns a singleton defaulting to active auto regulation" do
    state = SolakonControlState.current

    assert_equal state, SolakonControlState.current
    assert_equal false, state.auto_regulation_paused
    assert state.auto_regulation_active?
  end

  test "pause and resume change persistent runtime state" do
    state = SolakonControlState.current

    state.pause_auto_regulation!
    assert_not SolakonControlState.current.auto_regulation_active?

    state.resume_auto_regulation!
    assert SolakonControlState.current.auto_regulation_active?
  end

  test "last_decision is nil before the first remembered decision" do
    assert_nil SolakonControlState.current.last_decision
  end

  test "remember_decision! round-trips the decision through the database" do
    decision = ZeroExportController::Decision.new(state: :protected, target_w: 85, trim: true)

    SolakonControlState.current.remember_decision!(decision)

    previous = SolakonControlState.current.last_decision
    assert_equal :protected, previous.state
    assert_equal 85, previous.target_w
    assert previous.trim
  end

  test "failure counter increments, returns the count, and resets" do
    state = SolakonControlState.current

    assert_equal 1, state.register_failure!
    assert_equal 2, state.register_failure!

    state.reset_failures!

    assert_equal 1, SolakonControlState.current.register_failure!
  end
end
