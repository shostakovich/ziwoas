require "test_helper"

class SolakonControlStateTest < ActiveSupport::TestCase
  setup { SolakonControlState.delete_all if defined?(SolakonControlState) }

  test "current returns a singleton defaulting to active auto regulation" do
    state = SolakonControlState.current

    assert_equal state, SolakonControlState.current
    assert_equal false, state.auto_regulation_paused
    assert state.auto_regulation_active?
  end

  test "pause and resume change persistent runtime state and reset the decision" do
    state = SolakonControlState.current
    state.remember_decision!(ZeroExportController::Decision.new(state: :surplus, target_w: 500, trim: false))

    state.pause_auto_regulation!
    assert_not SolakonControlState.current.auto_regulation_active?

    state.resume_auto_regulation!
    assert SolakonControlState.current.auto_regulation_active?
    assert_nil SolakonControlState.current.last_decision
  end

  test "last_decision is nil before the first remembered decision" do
    assert_nil SolakonControlState.current.last_decision
  end

  test "remember_decision! round-trips the decision through the database" do
    decision = ZeroExportController::Decision.new(state: :protected, target_w: 85, trim: true)
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)

    SolakonControlState.current.remember_decision!(decision, at: now)

    previous = SolakonControlState.current.last_decision(at: now + 149.seconds)
    assert_equal :protected, previous.state
    assert_equal 85, previous.target_w
    assert previous.trim
  end

  test "last decision expires with the inverter watchdog" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)
    decision = ZeroExportController::Decision.new(state: :surplus, target_w: 500, trim: false)
    state = SolakonControlState.current
    state.remember_decision!(decision, at: now)

    assert_nil state.last_decision(at: now + SolakonClient::REMOTE_TIMEOUT_S.seconds)
  end

  test "reset_decision clears all controller memory" do
    state = SolakonControlState.current
    state.remember_decision!(ZeroExportController::Decision.new(state: :probe, target_w: 150, trim: false))

    state.reset_decision!

    assert_nil state.reload.last_decision
    assert_nil state.last_target_w
    assert_nil state.last_decision_at
    refute state.trim
  end

  test "failure counter increments, returns the count, and resets" do
    state = SolakonControlState.current

    assert_equal 1, state.register_failure!
    assert_equal 2, state.register_failure!

    state.reset_failures!

    assert_equal 1, SolakonControlState.current.register_failure!
  end
end

class SolakonControlStateDecisionTest < ActiveSupport::TestCase
  cover "SolakonControlState#last_decision"
  cover "SolakonControlState#remember_decision!"
  cover "SolakonControlState#reset_decision!"
  cover "SolakonControlState#resume_auto_regulation!"

  def state_with(control_state: "surplus", trim: false, target_w: 500, decided_at:)
    SolakonControlState.new(
      control_state: control_state,
      trim: trim,
      last_target_w: target_w,
      last_decision_at: decided_at
    )
  end

  test "last_decision requires both state and timestamp" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)

    assert_nil state_with(control_state: nil, decided_at: now).last_decision(at: now)
    assert_nil state_with(decided_at: nil).last_decision(at: now)
  end

  test "last_decision round trips every decision field before timeout" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)
    state = state_with(control_state: "protected", trim: true, target_w: 85, decided_at: now)

    assert_equal ZeroExportController::Decision.new(state: :protected, target_w: 85, trim: true),
                 state.last_decision(at: now + SolakonClient::REMOTE_TIMEOUT_S.seconds - 1.second)
  end

  test "last_decision expires at the exact watchdog boundary" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)
    state = state_with(decided_at: now)

    assert_nil state.last_decision(at: now + SolakonClient::REMOTE_TIMEOUT_S.seconds)
    assert_nil state.last_decision(at: now + SolakonClient::REMOTE_TIMEOUT_S.seconds + 1.second)
  end

  test "last_decision defaults to the current time" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)
    state = state_with(decided_at: now)

    travel_to(now + 1.second) do
      assert_equal :surplus, state.last_decision.state
    end
  end

  test "remember_decision writes the complete snapshot and timestamp" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)
    decision = ZeroExportController::Decision.new(state: :probe, target_w: 150, trim: true)
    state = SolakonControlState.new
    written = nil

    state.stub(:update!, ->(**attributes) { written = attributes }) do
      state.remember_decision!(decision, at: now)
    end

    assert_equal({ control_state: "probe", trim: true, last_target_w: 150, last_decision_at: now }, written)
  end

  test "remember_decision defaults to the current time" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)
    decision = ZeroExportController::Decision.new(state: :normal, target_w: 100, trim: false)
    state = SolakonControlState.new
    written = nil

    travel_to(now) do
      state.stub(:update!, ->(**attributes) { written = attributes }) do
        state.remember_decision!(decision)
      end
    end

    assert_equal now, written.fetch(:last_decision_at)
    assert_equal false, written.fetch(:trim)
  end

  test "reset_decision clears every controller field" do
    state = SolakonControlState.new
    written = nil

    state.stub(:update!, ->(**attributes) { written = attributes }) { state.reset_decision! }

    assert_equal({ control_state: nil, trim: false, last_target_w: nil, last_decision_at: nil }, written)
  end

  test "resume enables automation and clears every controller field" do
    state = SolakonControlState.new
    written = nil

    state.stub(:update!, ->(**attributes) { written = attributes }) { state.resume_auto_regulation! }

    assert_equal({ auto_regulation_paused: false, control_state: nil, trim: false,
                   last_target_w: nil, last_decision_at: nil }, written)
  end
end
