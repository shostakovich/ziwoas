require "test_helper"

class ControlOutcomeTest < ActiveSupport::TestCase
  cover "Solakon::Control::Outcome*"

  def decision(state: :surplus, target_w: 485, trim: false)
    Solakon::Control::Decision.new(state: state, target_w: target_w, trim: trim)
  end

  def reading(soc: 100, temp: 30.5, pv: 0, battery: -15.5)
    Solakon::Reading.new(battery_soc_pct: soc, battery_temperature_c: temp,
                         pv_power_w: pv, battery_power_w: battery)
  end

  test "an applied tick reports every control input" do
    outcome = Solakon::Control::Outcome.applied(
      decision: decision,
      load: Solakon::Control::Load.new(current_w: 123.6, floor_w: 84.6),
      reading: reading
    )

    assert outcome.applied?
    assert_equal :info, outcome.log_level
    assert_equal "state=surplus target=485W load=124W floor=85W " \
                 "soc=100% temp=30.5C pv=0.0W battery=-15.5W", outcome.log_line
  end

  test "a missing live measurement is named, not counted as zero" do
    outcome = Solakon::Control::Outcome.applied(
      decision: decision(state: :normal, target_w: 85),
      load: Solakon::Control::Load.new(current_w: nil, floor_w: 85),
      reading: reading(soc: 55, temp: 30, pv: 100, battery: 0)
    )

    assert_includes outcome.log_line, "load=stale"
    assert_includes outcome.log_line, "floor=85W"
  end

  test "a paused loop says so and nothing else" do
    outcome = Solakon::Control::Outcome.paused

    assert_not outcome.applied?
    assert_equal :info, outcome.log_level
    assert_equal "runtime paused", outcome.log_line
  end

  test "a write failure counts towards the release threshold" do
    outcome = Solakon::Control::Outcome.failed(failures: 2, error: "down")

    assert_equal :warn, outcome.log_level
    assert_equal "Modbus failure 2/3: down", outcome.log_line
  end

  test "the last failure says that remote control was handed back" do
    outcome = Solakon::Control::Outcome.released(failures: 3, error: "down")

    assert_equal :warn, outcome.log_level
    assert_equal "Modbus failure 3/3: down — relinquished remote control", outcome.log_line
  end
end
