require "test_helper"

class ZeroExportControllerTest < ActiveSupport::TestCase
  cover "ZeroExportController*"

  def reading(soc:, pv:, temp: 30.0, battery: 0)
    SolakonReading.new(taken_at: Time.current, active_power_w: 0, pv_power_w: pv,
                       battery_power_w: battery, battery_soc_pct: soc, battery_temperature_c: temp)
  end

  def load(current:, floor: 85.0)
    LoadEstimate.new(current_w: current, floor_w: floor)
  end

  def decide(reading:, load:, previous: nil)
    ZeroExportController.decide(reading: reading, load: load, previous: previous)
  end

  def previous(state:, target_w: nil, trim: false)
    ZeroExportController::Decision.new(state: state, target_w: target_w, trim: trim)
  end

  test "low soc entry starts from the derated PV estimate" do
    decision = decide(reading: reading(soc: 10, pv: 100), load: load(current: 386))

    assert_equal :protected, decision.state
    assert_equal 85, decision.target_w
  end

  test "low soc trim lowers the target while the battery discharges" do
    decision = decide(reading: reading(soc: 10, pv: 100, battery: -40), load: load(current: 386),
                      previous: previous(state: :protected, target_w: 85, trim: true))

    assert_equal :protected, decision.state
    assert_equal 58, decision.target_w
  end

  test "low soc trim raises the target while the battery charges above the bias" do
    decision = decide(reading: reading(soc: 10, pv: 300, battery: 80), load: load(current: 386),
                      previous: previous(state: :protected, target_w: 85, trim: true))

    assert_equal 118, decision.target_w
  end

  test "low soc trim stays within PV and measured load" do
    pv_limited = decide(reading: reading(soc: 10, pv: 100, battery: 200), load: load(current: 386),
                        previous: previous(state: :protected, target_w: 90, trim: true))
    load_limited = decide(reading: reading(soc: 10, pv: 300, battery: 200), load: load(current: 120),
                          previous: previous(state: :protected, target_w: 110, trim: true))

    assert_equal 100, pv_limited.target_w
    assert_equal 120, load_limited.target_w
  end

  test "low soc trim clamps at zero" do
    decision = decide(reading: reading(soc: 10, pv: 100, battery: -100), load: load(current: 386),
                      previous: previous(state: :protected, target_w: 10, trim: true))

    assert_equal 0, decision.target_w
  end

  test "entering low soc protection ignores a stale target" do
    from_normal = decide(reading: reading(soc: 10, pv: 100, battery: -40), load: load(current: 386),
                         previous: previous(state: :normal, target_w: 300))
    from_thermal = decide(reading: reading(soc: 10, pv: 700, battery: -200, temp: 45.0),
                          load: load(current: 386),
                          previous: previous(state: :protected, target_w: 800, trim: false))

    assert_equal 85, from_normal.target_w
    assert_equal 328, from_thermal.target_w
  end

  test "low soc trim respects the thermal ceiling" do
    decision = decide(reading: reading(soc: 10, pv: 700, battery: 200, temp: 48.0),
                      load: load(current: 386),
                      previous: previous(state: :protected, target_w: 386, trim: true))

    assert_equal 200, decision.target_w
  end

  test "low soc trim converges to the charging bias" do
    target = 85
    6.times do
      decision = decide(reading: reading(soc: 10, pv: 100, battery: 88 - target),
                        load: load(current: 386),
                        previous: previous(state: :protected, target_w: target, trim: true))
      target = decision.target_w
    end

    assert_in_delta 74, target, 1
  end

  test "normal mode uses live load immediately without a previous target" do
    decision = decide(reading: reading(soc: 55, pv: 100), load: load(current: 386))

    assert_equal :normal, decision.state
    assert_equal 386, decision.target_w
  end

  test "previous defaults to nil" do
    decision = ZeroExportController.decide(
      reading: reading(soc: 55, pv: 100),
      load: load(current: 386)
    )

    assert_equal previous(state: :normal, target_w: 386), decision
  end

  test "negative measured load is clamped to zero" do
    decision = decide(reading: reading(soc: 55, pv: 0), load: load(current: -10))

    assert_equal previous(state: :normal, target_w: 0), decision
  end

  test "normal mode covers refrigerator rises within 200 watts" do
    decision = decide(reading: reading(soc: 55, pv: 0), load: load(current: 180),
                      previous: previous(state: :normal, target_w: 60))

    assert_equal 180, decision.target_w
  end

  test "normal mode limits a large rise to 200 watts per tick" do
    first = decide(reading: reading(soc: 55, pv: 0), load: load(current: 2_000),
                   previous: previous(state: :normal, target_w: 60))
    second = decide(reading: reading(soc: 55, pv: 0), load: load(current: 2_000), previous: first)

    assert_equal 260, first.target_w
    assert_equal 460, second.target_w
  end

  test "normal mode follows a falling load immediately" do
    decision = decide(reading: reading(soc: 55, pv: 0), load: load(current: 120),
                      previous: previous(state: :normal, target_w: 600))

    assert_equal 120, decision.target_w
  end

  test "normal mode falls back to the guaranteed floor" do
    decision = decide(reading: reading(soc: 55, pv: 0), load: load(current: nil, floor: 85))

    assert_equal 85, decision.target_w
  end

  test "target never exceeds 800 watts" do
    decision = decide(reading: reading(soc: 90, pv: 0), load: load(current: 2_000))

    assert_equal :normal, decision.state
    assert_equal 800, decision.target_w
  end

  test "charging at 99 percent enters surplus and raises output" do
    decision = decide(reading: reading(soc: 99, pv: 300, battery: 165), load: load(current: 100),
                      previous: previous(state: :normal, target_w: 100))

    assert_equal :surplus, decision.state
    assert_equal 250, decision.target_w
  end

  test "production full-charge traces enter surplus or probe before staying curtailed" do
    charging_traces = [
      [ 99, 197, 124 ],
      [ 99, 182, 108 ],
      [ 99, 228, 148 ],
      [ 99, 188, 113 ],
      [ 99, 187, 113 ],
      [ 99, 246, 176 ]
    ]

    charging_traces.each do |soc, pv, battery|
      decision = decide(reading: reading(soc: soc, pv: pv, battery: battery),
                        load: load(current: 100),
                        previous: previous(state: :normal, target_w: 100))

      assert_equal :surplus, decision.state
      assert_operator decision.target_w, :>, 100
    end

    before_jump = decide(reading: reading(soc: 98, pv: 193, battery: 112),
                         load: load(current: 100),
                         previous: previous(state: :normal, target_w: 100))
    after_jump = decide(reading: reading(soc: 100, pv: 0, battery: -69),
                        load: load(current: 100), previous: before_jump)

    assert_equal :normal, before_jump.state
    assert_equal :probe, after_jump.state
    assert_equal 150, after_jump.target_w
  end

  test "surplus rise and fall have separate limits" do
    rise = decide(reading: reading(soc: 100, pv: 0, battery: 500), load: load(current: 100),
                  previous: previous(state: :surplus, target_w: 100))
    fall = decide(reading: reading(soc: 100, pv: 0, battery: -500), load: load(current: 100),
                  previous: previous(state: :surplus, target_w: 700))

    assert_equal 300, rise.target_w
    assert_equal 400, fall.target_w
    assert_equal :surplus, fall.state
  end

  test "surplus holds inside the deadband and ignores curtailed PV" do
    decision = decide(reading: reading(soc: 100, pv: 0, battery: 15), load: load(current: 100),
                      previous: previous(state: :surplus, target_w: 400))

    assert_equal :surplus, decision.state
    assert_equal 400, decision.target_w
  end

  test "surplus never falls below the normal ramp target" do
    decision = decide(reading: reading(soc: 100, pv: 0, battery: -100), load: load(current: 180),
                      previous: previous(state: :surplus, target_w: 200))

    assert_equal :surplus_exhausted, decision.state
    assert_equal 180, decision.target_w
  end

  test "surplus converges to the battery deadband" do
    target = 100
    state = :normal

    4.times do
      decision = decide(reading: reading(soc: 100, pv: 600, battery: 600 - target),
                        load: load(current: 100), previous: previous(state: state, target_w: target))
      state = decision.state
      target = decision.target_w
    end

    assert_equal :surplus, state
    assert_equal 585, target
  end

  test "surplus exit requires a confirming discharge tick" do
    exhausted = decide(reading: reading(soc: 100, pv: 0, battery: -60), load: load(current: 100),
                       previous: previous(state: :surplus, target_w: 120))
    blocked = decide(reading: reading(soc: 100, pv: 0, battery: -40), load: load(current: 100),
                     previous: exhausted)

    assert_equal :surplus_exhausted, exhausted.state
    assert_equal :probe_blocked, blocked.state
    assert_equal 100, blocked.target_w
  end

  test "charging cancels a pending surplus exit" do
    decision = decide(reading: reading(soc: 100, pv: 0, battery: 100), load: load(current: 100),
                      previous: previous(state: :surplus_exhausted, target_w: 100))

    assert_equal :surplus, decision.state
    assert_equal 185, decision.target_w
  end

  test "surplus exit holds while battery power is inside the deadband" do
    decision = decide(reading: reading(soc: 100, pv: 0, battery: 0), load: load(current: 100),
                      previous: previous(state: :surplus_exhausted, target_w: 100))

    assert_equal previous(state: :surplus_exhausted, target_w: 100), decision
  end

  test "surplus exit returns to normal below 99 percent" do
    decision = decide(reading: reading(soc: 98, pv: 0, battery: 0), load: load(current: 100),
                      previous: previous(state: :surplus_exhausted, target_w: 100))

    assert_equal previous(state: :normal, target_w: 100), decision
  end

  test "falling below 99 percent leaves surplus" do
    decision = decide(reading: reading(soc: 98, pv: 0, battery: -40), load: load(current: 100),
                      previous: previous(state: :surplus, target_w: 300))

    assert_equal :normal, decision.state
    assert_equal 100, decision.target_w
  end

  test "full curtailed battery starts one 50 watt probe" do
    decision = decide(reading: reading(soc: 100, pv: 0, battery: -60), load: load(current: 100),
                      previous: previous(state: :normal, target_w: 100))

    assert_equal :probe, decision.state
    assert_equal 150, decision.target_w
  end

  test "successful probe becomes surplus and holds its target" do
    decision = decide(reading: reading(soc: 100, pv: 0, battery: -15), load: load(current: 100),
                      previous: previous(state: :probe, target_w: 150))

    assert_equal :surplus, decision.state
    assert_equal 150, decision.target_w
  end

  test "probe returns to normal below 99 percent" do
    decision = decide(reading: reading(soc: 98, pv: 0, battery: 0), load: load(current: 100),
                      previous: previous(state: :probe, target_w: 150))

    assert_equal previous(state: :normal, target_w: 100), decision
  end

  test "failed probe returns to normal target and blocks another probe" do
    failed = decide(reading: reading(soc: 100, pv: 0, battery: -40), load: load(current: 100),
                    previous: previous(state: :probe, target_w: 150))
    next_tick = decide(reading: reading(soc: 100, pv: 0, battery: -40), load: load(current: 100),
                       previous: failed)

    assert_equal :probe_blocked, failed.state
    assert_equal 100, failed.target_w
    assert_equal :probe_blocked, next_tick.state
    assert_equal 100, next_tick.target_w
  end

  test "probe block resets below 99 percent" do
    decision = decide(reading: reading(soc: 98, pv: 0, battery: -40), load: load(current: 100),
                      previous: previous(state: :probe_blocked, target_w: 100))

    assert_equal previous(state: :normal, target_w: 100), decision
  end

  test "visible charging overrides a probe block" do
    decision = decide(reading: reading(soc: 100, pv: 0, battery: 100), load: load(current: 100),
                      previous: previous(state: :probe_blocked, target_w: 100))

    assert_equal :surplus, decision.state
    assert_equal 185, decision.target_w
  end

  test "probe is blocked when there is no output headroom" do
    decision = decide(reading: reading(soc: 100, pv: 0, battery: 0), load: load(current: 900))

    assert_equal :probe_blocked, decision.state
    assert_equal 800, decision.target_w
  end

  test "visible PV at full charge keeps normal operation when no surplus is measured" do
    decision = decide(reading: reading(soc: 100, pv: 50, battery: 0), load: load(current: 100),
                      previous: previous(state: :normal, target_w: 100))

    assert_equal previous(state: :normal, target_w: 100), decision
  end

  test "thermal protection takes priority over surplus and probe" do
    decision = decide(reading: reading(soc: 100, pv: 700, battery: 200, temp: 49.0),
                      load: load(current: 900),
                      previous: previous(state: :surplus, target_w: 700))

    assert_equal :protected, decision.state
    assert_equal 0, decision.target_w
  end

  test "thermal ceiling ramps linearly from 800 watts to zero" do
    high = load(current: 900)

    assert_equal 800, decide(reading: reading(soc: 55, pv: 700, temp: 45.0), load: high).target_w
    assert_equal 600, decide(reading: reading(soc: 55, pv: 700, temp: 46.0), load: high).target_w
    assert_equal 400, decide(reading: reading(soc: 55, pv: 700, temp: 47.0), load: high).target_w
    assert_equal 200, decide(reading: reading(soc: 55, pv: 700, temp: 48.0), load: high).target_w
    assert_equal 0, decide(reading: reading(soc: 55, pv: 700, temp: 49.0), load: high).target_w
  end

  test "thermal protection releases after cooling" do
    holding = decide(reading: reading(soc: 55, pv: 0, temp: 45.0), load: load(current: 900),
                     previous: previous(state: :protected))
    released = decide(reading: reading(soc: 55, pv: 0, temp: 44.9), load: load(current: 300),
                      previous: previous(state: :protected))

    assert_equal :protected, holding.state
    assert_equal :normal, released.state
  end

  test "controller helper boundaries are explicit" do
    controller = ZeroExportController
    baseline = 100
    prior = previous(state: :surplus, target_w: 400)

    assert_equal false, controller.battery_discharging?(reading(soc: 100, pv: 0, battery: nil))
    assert_equal false, controller.battery_discharging?(reading(soc: 100, pv: 0, battery: -15))
    assert_equal true, controller.battery_discharging?(reading(soc: 100, pv: 0, battery: -15.5))
    assert_equal true, controller.battery_discharging?(reading(soc: 100, pv: 0, battery: -16))
    assert_equal false, controller.charging_surplus?(reading(soc: 100, pv: 0, battery: nil))
    assert_equal false, controller.charging_surplus?(reading(soc: 100, pv: 0, battery: 15))
    assert_equal true, controller.charging_surplus?(reading(soc: 100, pv: 0, battery: 15.5))
    assert_equal true, controller.charging_surplus?(reading(soc: 100, pv: 0, battery: 16))

    assert_equal 0, controller.surplus_adjustment(15)
    assert_equal 0, controller.surplus_adjustment(-15)
    assert_equal 1, controller.surplus_adjustment(16)
    assert_equal(-1, controller.surplus_adjustment(-16))
    assert_equal 200, controller.surplus_adjustment(500)
    assert_equal(-300, controller.surplus_adjustment(-500))

    assert_equal baseline, controller.surplus_target(
      reading(soc: 100, pv: 0, battery: 100), baseline, nil
    )
    assert_equal 485, controller.surplus_target(
      reading(soc: 100, pv: 0, battery: 100), baseline, prior
    )
    assert_equal 385, controller.surplus_target(
      reading(soc: 100, pv: 0, battery: -30), baseline, prior
    )

    assert_equal false, controller.probe_candidate?(reading(soc: 99, pv: 0), 100)
    assert_equal false, controller.probe_candidate?(reading(soc: 100, pv: 50), 100)
    assert_equal false, controller.probe_candidate?(reading(soc: 100, pv: 0), 800)
    assert_equal true, controller.probe_candidate?(reading(soc: 100, pv: 0), 799)
    assert_equal false, controller.protecting?(reading(soc: 11, pv: 0, temp: 44.9), :protected)

    assert_equal [ :normal, 100 ], controller.start_unprotected_mode(
      reading(soc: 100, pv: 50, battery: 0), 100, previous(state: :normal, target_w: 100)
    )
    assert_equal [ :normal, 100 ], controller.continue_probe_block(
      reading(soc: 98, pv: 0, battery: 0), 100, previous(state: :probe_blocked, target_w: 100)
    )

    assert_equal [ :surplus, 100 ], controller.surplus_decision(
      reading(soc: 100, pv: 0, battery: 0), 100, previous(state: :surplus, target_w: 100)
    )
    assert_equal [ :surplus, 385 ], controller.surplus_decision(
      reading(soc: 100, pv: 0, battery: -30), 100, prior
    )
    controller.stub(:surplus_target, 99) do
      assert_equal [ :surplus_exhausted, 99 ], controller.surplus_decision(
        reading(soc: 100, pv: 0, battery: -30), 100, prior
      )
    end
    controller.stub(:surplus_target, 100.0) do
      assert_equal [ :surplus_exhausted, 100.0 ], controller.surplus_decision(
        reading(soc: 100, pv: 0, battery: -30), 100, prior
      )
    end

    nil_target = previous(state: :surplus, target_w: nil)
    assert_equal 100, controller.surplus_target(reading(soc: 100, pv: 0, battery: 100), 100, nil_target)
    assert_equal 100.5, controller.surplus_target(
      reading(soc: 100, pv: 0, battery: 15.5), 100, previous(state: :surplus, target_w: 100)
    )
    assert_equal 100, controller.surplus_target(
      reading(soc: 100, pv: 0, battery: nil), 100, previous(state: :surplus, target_w: 100)
    )

    assert_equal 100.5, controller.normal_target(load(current: 100.5), previous: nil)
    effective_nil = Struct.new(:effective_w).new(nil)
    assert_equal 0.0, controller.normal_target(effective_nil, previous: nil)

    assert_equal 0.0, controller.trimmed_target(
      reading(soc: 10, pv: nil, battery: 0), load(current: 100), previous: nil
    )
    assert_in_delta 85.425, controller.trimmed_target(
      reading(soc: 10, pv: 100.5, battery: 0), load(current: 200), previous: nil
    )
    assert_equal 85.0, controller.trimmed_target(
      reading(soc: 10, pv: 100, battery: 0), load(current: 200),
      previous: previous(state: :protected, target_w: nil, trim: true)
    )
    assert_equal 77.5, controller.trimmed_target(
      reading(soc: 10, pv: 100, battery: nil), load(current: 200),
      previous: previous(state: :protected, target_w: 85, trim: true)
    )
    assert_equal 82.25, controller.trimmed_target(
      reading(soc: 10, pv: 100, battery: 9.5), load(current: 200),
      previous: previous(state: :protected, target_w: 85, trim: true)
    )
    assert_equal 0.0, controller.trimmed_target(
      reading(soc: 10, pv: 100, battery: -100), load(current: 200),
      previous: previous(state: :protected, target_w: 10, trim: true)
    )

    assert_equal 800, controller.thermal_ceiling_w(reading(soc: 55, pv: 0, temp: nil))
    assert_equal 733, controller.thermal_ceiling_w(reading(soc: 55, pv: 0, temp: 45.333))
    assert_equal 0, controller.thermal_ceiling_w(reading(soc: 55, pv: 0, temp: 50))
    inconsistent_hot_reading = Struct.new(:battery_temperature_c) do
      def battery_cooled? = false
    end.new(44)
    assert_equal 800, controller.thermal_ceiling_w(inconsistent_hot_reading)
  end

  test "decision conversion and clamps handle internal boundary values" do
    controller = ZeroExportController
    reading_value = reading(soc: 55, pv: 0)

    controller.stub(:protecting?, false) do
      controller.stub(:unprotected_decision, [ :normal, nil ]) do
        assert_equal previous(state: :normal, target_w: 0),
                     controller.decide(reading: reading_value, load: load(current: 100))
      end
      controller.stub(:unprotected_decision, [ :normal, 2_000 ]) do
        controller.stub(:thermal_ceiling_w, 1_000) do
          assert_equal previous(state: :normal, target_w: 800),
                       controller.decide(reading: reading_value, load: load(current: 100))
        end
      end
    end
  end

  test "only low soc protection is marked as trimming" do
    low = decide(reading: reading(soc: 10, pv: 100), load: load(current: 386))
    hot = decide(reading: reading(soc: 55, pv: 0, temp: 45.0), load: load(current: 180))
    normal = decide(reading: reading(soc: 55, pv: 100), load: load(current: 386))

    assert low.trim
    refute hot.trim
    refute normal.trim
  end
end
