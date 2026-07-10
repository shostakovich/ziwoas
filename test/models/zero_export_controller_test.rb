require "test_helper"

class ZeroExportControllerTest < ActiveSupport::TestCase
  setup { @tz = Time.zone; Time.zone = "Europe/Berlin" }
  teardown { Time.zone = @tz }

  def reading(soc:, pv:, temp: 30.0, battery: 0)
    SolakonReading.new(taken_at: Time.current, active_power_w: 0, pv_power_w: pv,
                       battery_power_w: battery, battery_soc_pct: soc, battery_temperature_c: temp)
  end

  def load(current:, median: nil)
    attrs = { current_w: current, floor_w: 85.0 }
    attrs[:median_w] = median unless median.nil?
    LoadEstimate.new(**attrs)
  end

  def decide(reading:, load:, previous: nil)
    ZeroExportController.decide(reading: reading, load: load, previous: previous)
  end

  def previous(state:, target_w: nil, trim: false)
    ZeroExportController::Decision.new(state: state, target_w: target_w, trim: trim)
  end

  test "low soc entry starts from the derated PV estimate" do
    d = decide(reading: reading(soc: 10, pv: 100), load: load(current: 386))
    assert_equal :protected, d.state
    assert_equal 85, d.target_w # 0.85 × min(pv, load)
  end

  test "low soc trim lowers the target while the battery discharges" do
    d = decide(reading: reading(soc: 10, pv: 100, battery: -40), load: load(current: 386),
               previous: previous(state: :protected, target_w: 85, trim: true))
    assert_equal :protected, d.state
    assert_equal 58, d.target_w # 85 + 0.5 × (−40 − 15) = 57.5 → 58
  end

  test "low soc trim raises the target while the battery charges above the bias" do
    d = decide(reading: reading(soc: 10, pv: 300, battery: 80), load: load(current: 386),
               previous: previous(state: :protected, target_w: 85, trim: true))
    assert_equal 118, d.target_w # 85 + 0.5 × (80 − 15) = 117.5 → 118
  end

  test "low soc trim never exceeds pv" do
    d = decide(reading: reading(soc: 10, pv: 100, battery: 200), load: load(current: 386),
               previous: previous(state: :protected, target_w: 90, trim: true))
    assert_equal 100, d.target_w # 90 + 92.5 clamped at pv
  end

  test "low soc trim never exceeds the load" do
    d = decide(reading: reading(soc: 10, pv: 300, battery: 200), load: load(current: 120),
               previous: previous(state: :protected, target_w: 110, trim: true))
    assert_equal 120, d.target_w # clamped at the measured load
  end

  test "low soc trim clamps at zero" do
    d = decide(reading: reading(soc: 10, pv: 100, battery: -100), load: load(current: 386),
               previous: previous(state: :protected, target_w: 10, trim: true))
    assert_equal 0, d.target_w # 10 − 57.5 → clamped
  end

  test "low soc entry applies when the previous state was not protected" do
    d = decide(reading: reading(soc: 10, pv: 100, battery: -40), load: load(current: 386),
               previous: previous(state: :normal, target_w: 300))
    assert_equal 85, d.target_w # fresh entry ignores the stale normal-mode target
  end

  test "low soc entry applies when the previous tick was protected but not trimming" do
    # Thermal protection at good SoC follows the load with a high target; when the
    # SoC then hits the minimum, the first trim tick must derate, not continue
    # from the stale thermal target.
    d = decide(reading: reading(soc: 10, pv: 700, battery: -200, temp: 45.0), load: load(current: 386),
               previous: previous(state: :protected, target_w: 800, trim: false))
    assert_equal 328, d.target_w # 0.85 × min(pv, load) — not the un-derated min(pv, load)
  end

  test "low soc trim respects the thermal ceiling" do
    d = decide(reading: reading(soc: 10, pv: 700, battery: 200, temp: 48.0), load: load(current: 386),
               previous: previous(state: :protected, target_w: 386, trim: true))
    assert_equal 200, d.target_w # trim would allow 386, the 48C ceiling caps it
  end

  test "low soc trim converges to the bias operating point without oscillating" do
    # Simple plant model: the battery absorbs whatever the AC target leaves over,
    # neutral at 88W (PV minus conversion losses). Fixed point: battery ≈ +15W.
    target = 85
    6.times do
      d = decide(reading: reading(soc: 10, pv: 100, battery: 88 - target), load: load(current: 386),
                 previous: previous(state: :protected, target_w: target, trim: true))
      target = d.target_w
    end
    assert_in_delta 74, target, 1 # 85 → 79 → 76 → 75 → 74 → stable
  end

  test "normal mode covers the measured load from PV and battery" do
    d = decide(reading: reading(soc: 55, pv: 100), load: load(current: 386))
    assert_equal :normal, d.state
    assert_equal 386, d.target_w # full load, no battery-help cap
  end

  test "normal mode covers the load from the battery at night too" do
    d = decide(reading: reading(soc: 55, pv: 0), load: load(current: 300))
    assert_equal :normal, d.state
    assert_equal 300, d.target_w
  end

  test "hot battery enters protected and follows load capped at 800" do
    d = decide(reading: reading(soc: 55, pv: 700, temp: 45.0), load: load(current: 900))
    assert_equal :protected, d.state
    assert_equal 800, d.target_w
  end

  test "hot battery still tracks a low load below the 800 ceiling" do
    d = decide(reading: reading(soc: 55, pv: 0, temp: 45.0), load: load(current: 180))
    assert_equal :protected, d.state
    assert_equal 180, d.target_w
  end

  test "thermal ceiling ramps linearly from 800W at 45C to 0W at 49C" do
    high = load(current: 900)
    assert_equal 800, decide(reading: reading(soc: 55, pv: 700, temp: 45.0), load: high).target_w
    assert_equal 600, decide(reading: reading(soc: 55, pv: 700, temp: 46.0), load: high).target_w
    assert_equal 400, decide(reading: reading(soc: 55, pv: 700, temp: 47.0), load: high).target_w
    assert_equal 200, decide(reading: reading(soc: 55, pv: 700, temp: 48.0), load: high).target_w
    assert_equal 0,   decide(reading: reading(soc: 55, pv: 700, temp: 49.0), load: high).target_w
  end

  test "above 49C discharge stays at zero" do
    d = decide(reading: reading(soc: 55, pv: 700, temp: 52.0), load: load(current: 900))
    assert_equal :protected, d.state
    assert_equal 0, d.target_w
  end

  test "throttled output still tracks a lower load" do
    d = decide(reading: reading(soc: 55, pv: 0, temp: 48.0), load: load(current: 150))
    assert_equal :protected, d.state
    assert_equal 150, d.target_w # below the 200W ceiling at 48C
  end

  test "thermal de-rating applies even at full charge" do
    d = decide(reading: reading(soc: 100, pv: 700, temp: 49.0), load: load(current: 900))
    assert_equal 0, d.target_w
  end

  test "thermal protection holds at 45.0 and releases at 44.9 (no hysteresis)" do
    d = decide(reading: reading(soc: 55, pv: 0, temp: 45.0), load: load(current: 900),
               previous: previous(state: :protected))
    assert_equal :protected, d.state
    assert_equal 800, d.target_w
  end

  test "thermal protection releases once cooled below 45" do
    d = decide(reading: reading(soc: 55, pv: 0, temp: 44.9), load: load(current: 300),
               previous: previous(state: :protected))
    assert_equal :normal, d.state
  end

  test "target never exceeds the legal cap" do
    d = decide(reading: reading(soc: 90, pv: 0), load: load(current: 2000))
    assert_equal :normal, d.state
    assert_equal 800, d.target_w
  end

  test "median cap applies in normal mode" do
    d = decide(reading: reading(soc: 55, pv: 100), load: load(current: 800, median: 240))
    assert_equal :normal, d.state
    assert_equal 240, d.target_w
  end

  test "median cap applies in protected output" do
    d = decide(reading: reading(soc: 55, pv: 0, temp: 45.0), load: load(current: 800, median: 240))
    assert_equal :protected, d.state
    assert_equal 240, d.target_w
  end

  test "load drop follows current load below median immediately" do
    d = decide(reading: reading(soc: 90, pv: 0), load: load(current: 120, median: 240))
    assert_equal :normal, d.state
    assert_equal 120, d.target_w
  end

  test "decide marks only low-soc protection as trimming" do
    low = decide(reading: reading(soc: 10, pv: 100), load: load(current: 386))
    assert low.trim

    hot = decide(reading: reading(soc: 55, pv: 0, temp: 45.0), load: load(current: 180))
    assert_equal :protected, hot.state
    refute hot.trim

    normal = decide(reading: reading(soc: 55, pv: 100), load: load(current: 386))
    refute normal.trim
  end
end
