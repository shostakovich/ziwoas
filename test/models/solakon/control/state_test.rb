require "test_helper"

class ControlStateTest < ActiveSupport::TestCase
  cover "Solakon::Control::State*"

  setup { Solakon::Control::State.delete_all }

  def decision(state: :surplus, target_w: 500, trim: false)
    Solakon::Control::Decision.new(state: state, target_w: target_w, trim: trim)
  end

  test "current returns a singleton defaulting to active auto regulation" do
    state = Solakon::Control::State.current

    assert_equal state, Solakon::Control::State.current
    assert_equal false, state.paused
    assert state.active?
  end

  test "pause and resume change persistent runtime state and clear what was stored" do
    state = Solakon::Control::State.current
    state.store!(decision, at: Time.current)

    state.pause!
    assert_not Solakon::Control::State.current.active?

    state.resume!
    assert Solakon::Control::State.current.active?
    assert_nil Solakon::Control::State.current.stored
  end

  test "nothing is stored before the first tick" do
    assert_nil Solakon::Control::State.current.stored
  end

  test "store! round-trips the decision and its timestamp through the database" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)

    Solakon::Control::State.current.store!(decision(state: :protected, target_w: 85, trim: true), at: now)

    stored = Solakon::Control::State.current.stored
    assert_equal Solakon::Control::Decision.new(state: :protected, target_w: 85, trim: true), stored.decision
    assert_equal now, stored.at
  end

  test "clear! forgets everything the last tick wrote" do
    state = Solakon::Control::State.current
    state.store!(decision(state: :probe, target_w: 150), at: Time.current)

    state.clear!

    assert_nil state.reload.stored
    assert_nil state.last_target_w
    assert_nil state.last_decision_at
    refute state.trim
  end

  test "failure counter increments, returns the count, and resets" do
    state = Solakon::Control::State.current

    assert_equal 1, state.count_failure!
    assert_equal 2, state.count_failure!
    assert_equal 2, state.failures

    state.reset_failures!

    assert_equal 0, Solakon::Control::State.current.failures
  end

  test "reset_failures! is a no-op when the count is already zero" do
    state = Solakon::Control::State.new
    called = false

    state.stub(:update!, ->(**) { called = true }) do
      state.reset_failures!
    end

    refute called
  end
end

class ControlStateStoredTest < ActiveSupport::TestCase
  cover "Solakon::Control::State#stored"
  cover "Solakon::Control::State#store!"
  cover "Solakon::Control::State#clear!"
  cover "Solakon::Control::State#resume!"
  cover "Solakon::Control::Stored*"

  def state_with(decision_state: "surplus", trim: false, target_w: 500, decided_at:)
    Solakon::Control::State.new(
      decision_state: decision_state,
      trim: trim,
      last_target_w: target_w,
      last_decision_at: decided_at
    )
  end

  test "a stored decision needs both the state and the timestamp" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)

    assert_nil state_with(decision_state: nil, decided_at: now).stored
    assert_nil state_with(decided_at: nil).stored
  end

  test "stored round trips every decision field" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)
    stored = state_with(decision_state: "protected", trim: true, target_w: 85, decided_at: now).stored

    assert_equal :protected, stored.decision_state
    assert_equal 85, stored.target_w
    assert stored.trim
    assert_equal now, stored.at
    assert_equal Solakon::Control::Decision.new(state: :protected, target_w: 85, trim: true), stored.decision
  end

  test "store! writes the complete decision and the timestamp" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)
    decision = Solakon::Control::Decision.new(state: :probe, target_w: 150, trim: true)
    state = Solakon::Control::State.new
    written = nil

    state.stub(:update!, ->(**attributes) { written = attributes }) do
      state.store!(decision, at: now)
    end

    assert_equal({ decision_state: "probe", trim: true, last_target_w: 150, last_decision_at: now }, written)
  end

  test "store! writes a non-trimming decision's trim as false" do
    now = Time.zone.local(2026, 9, 11, 12, 0, 0)
    decision = Solakon::Control::Decision.new(state: :normal, target_w: 150, trim: false)
    state = Solakon::Control::State.new
    written = nil

    state.stub(:update!, ->(**attributes) { written = attributes }) do
      state.store!(decision, at: now)
    end

    assert_equal({ decision_state: "normal", trim: false, last_target_w: 150, last_decision_at: now }, written)
  end

  test "clear! clears every stored field" do
    state = Solakon::Control::State.new
    written = nil

    state.stub(:update!, ->(**attributes) { written = attributes }) { state.clear! }

    assert_equal({ decision_state: nil, trim: false, last_target_w: nil, last_decision_at: nil }, written)
  end

  test "resume enables automation and clears every stored field" do
    state = Solakon::Control::State.new
    written = nil

    state.stub(:update!, ->(**attributes) { written = attributes }) { state.resume! }

    assert_equal({ paused: false, decision_state: nil, trim: false,
                   last_target_w: nil, last_decision_at: nil }, written)
  end
end
