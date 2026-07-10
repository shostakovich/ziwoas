require "test_helper"

class ZeroExportTickJobTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls
    def initialize(fail: false)
      @fail  = fail
      @calls = []
    end

    def apply_control!(power_w:, min_soc:)
      raise SolakonClient::Error, "down" if @fail
      @calls << [ :apply_power, power_w, min_soc ]
    end

    def release_control! = (@calls << :release)
  end

  Plug = Struct.new(:id, :role, :name, keyword_init: true)
  Sol  = Struct.new(:host, :port, :unit_id, :monitoring_enabled, :control_enabled,
                    :stale_after_s, keyword_init: true)
  Cfg  = Struct.new(:plugs, :solakon, :weather, :timezone, keyword_init: true)

  def config(monitoring_enabled: true, control_enabled: true, solakon: true)
    sol = if solakon
            Sol.new(host: "h", port: 502, unit_id: 1, monitoring_enabled: monitoring_enabled,
                    control_enabled: control_enabled, stale_after_s: 120)
    end
    Cfg.new(plugs: [ Plug.new(id: "fridge", role: :consumer, name: "Kühlschrank") ], solakon: sol,
            weather: nil, timezone: "Europe/Berlin")
  end

  setup do
    Sample.delete_all
    SolakonControlState.delete_all
    @cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    SolakonControlState.delete_all
  end

  def run_job(client:, state:, now: Time.at(1_000_000), cfg: config)
    Rails.stub(:cache, @cache) do
      ConfigLoader.stub(:app_config, cfg) do
        ZeroExportTickJob.new.perform(client: client, state: state, reader_now: now)
      end
    end
  end

  def healthy_state
    SolakonClient::State.new(battery_soc: 55, active_power_w: 250, pv_power_w: 0, battery_power_w: 0,
                              battery_temperature_c: 30)
  end

  def state_with(soc:, pv: 100, temp: 30, battery: 0)
    SolakonClient::State.new(battery_soc: soc, active_power_w: 0, pv_power_w: pv, battery_power_w: battery,
                              battery_temperature_c: temp)
  end

  test "applies control derived from measured consumption, with min_soc guard" do
    now = Time.at(1_000_000)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 250, aenergy_wh: 1)
    client = FakeClient.new
    run_job(client: client, state: healthy_state, now: now)
    assert_equal [ [ :apply_power, 250, 10 ] ], client.calls
  end

  test "remembers the applied decision as the control loop state" do
    now = Time.at(1_000_000)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 250, aenergy_wh: 1)

    run_job(client: FakeClient.new, state: healthy_state, now: now)

    previous = SolakonControlState.current.last_decision
    assert_equal :normal, previous.state
    assert_equal 250, previous.target_w
    refute previous.trim
  end

  test "caps a fresh consumption spike at the recent median" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    [ 240, 240, 240, 240, 800 ].each_with_index do |watts, i|
      Sample.create!(plug_id: "fridge", ts: (now - (25 - i * 5).minutes).to_i,
                     apower_w: watts, aenergy_wh: 1)
    end

    client = FakeClient.new

    run_job(client: client, state: healthy_state, now: now)

    assert_equal [ [ :apply_power, 240, 10 ] ], client.calls
  end

  test "fresh low consumption is not overridden by a stale cached floor" do
    now = Time.at(1_000_000)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 20, aenergy_wh: 1)
    @cache.write(ConsumptionReader::FLOOR_CACHE_KEY, 200.0) # stale, high cached floor
    client = FakeClient.new
    run_job(client: client, state: healthy_state, now: now)
    assert_equal [ [ :apply_power, 20, 10 ] ], client.calls # follows fresh load, not the floor
  end

  test "falls back to the floor when no fresh samples are available" do
    now = Time.at(1_000_000)
    # only a stale sample exists -> consumption unknown -> use floor (146)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 600, apower_w: 146, aenergy_wh: 1)
    client = FakeClient.new
    run_job(client: client, state: healthy_state, now: now)
    assert_equal [ [ :apply_power, 146, 10 ] ], client.calls
  end

  test "low soc entry writes the derated PV estimate" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 386, aenergy_wh: 1)
    client = FakeClient.new

    run_job(client: client, state: state_with(soc: 10, pv: 100, temp: 30), now: now)

    assert_equal [ [ :apply_power, 85, 10 ] ], client.calls
  end

  test "low soc trim corrects the next tick from the measured battery power" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 386, aenergy_wh: 1)

    run_job(client: FakeClient.new, state: state_with(soc: 10, pv: 100), now: now) # entry: writes 85
    second = FakeClient.new
    run_job(client: second, state: state_with(soc: 10, pv: 100, battery: -40), now: now + 30.seconds)

    assert_equal [ [ :apply_power, 58, 10 ] ], second.calls # 85 + 0.5 × (−40 − 15)
  end

  test "falling to low soc during thermal protection re-enters via the entry derate" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 386, aenergy_wh: 1)

    # Hot battery at good SoC: protected follows the load (writes 386).
    run_job(client: FakeClient.new, state: state_with(soc: 55, pv: 700, temp: 45), now: now)

    # SoC hits the minimum while still protected: the first trim tick must start
    # from the derated PV estimate, not continue from the stale thermal target.
    second = FakeClient.new
    run_job(client: second, state: state_with(soc: 10, pv: 700, temp: 45, battery: -200),
            now: now + 30.seconds)

    assert_equal [ [ :apply_power, 328, 10 ] ], second.calls # 0.85 × min(pv, load)
  end

  test "writes every tick even when the target is unchanged" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 386, aenergy_wh: 1)

    run_job(client: FakeClient.new, state: state_with(soc: 55, pv: 100, temp: 30), now: now)
    second = FakeClient.new
    run_job(client: second, state: state_with(soc: 55, pv: 100, temp: 30), now: now + 30.seconds)

    # Re-arms the inverter's 150s remote-control watchdog on every 30s tick.
    assert_equal [ [ :apply_power, 386, 10 ] ], second.calls
  end

  test "low soc trim applies small corrections on the very next tick" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 386, aenergy_wh: 1)

    run_job(client: FakeClient.new, state: state_with(soc: 10, pv: 100), now: now) # entry: writes 85
    second = FakeClient.new
    run_job(client: second, state: state_with(soc: 10, pv: 100, battery: 9), now: now + 30.seconds)

    assert_equal [ [ :apply_power, 82, 10 ] ], second.calls # 85 + 0.5 × (9 − 15)
  end

  test "hot battery clamps the whole target to 800W" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 900, aenergy_wh: 1)
    client = FakeClient.new

    run_job(client: client, state: state_with(soc: 55, pv: 700, temp: 45), now: now)

    assert_includes client.calls, [ :apply_power, 800, 10 ]
  end

  test "crossing the thermal cutoff writes a zero target" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 900, aenergy_wh: 1)

    # Warm: the de-rating ceiling is ~40 W at 48.8 C, written as the target.
    run_job(client: FakeClient.new, state: state_with(soc: 55, pv: 700, temp: 48.8), now: now)

    # Crossing the 49 C cutoff must write 0 W so the battery stops discharging.
    cutoff = FakeClient.new
    run_job(client: cutoff, state: state_with(soc: 55, pv: 700, temp: 49.0), now: now + 30.seconds)

    assert_includes cutoff.calls, [ :apply_power, 0, 10 ]
  end

  test "no-op when control is disabled" do
    client = FakeClient.new
    run_job(client: client, state: healthy_state, cfg: config(control_enabled: false))
    assert_empty client.calls
  end

  test "no-op when solakon not configured" do
    client = FakeClient.new
    run_job(client: client, state: healthy_state, cfg: config(solakon: false))
    assert_empty client.calls
  end

  test "a single failure does not raise, relinquish control, or advance the loop state" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 250, aenergy_wh: 1)
    client = FakeClient.new(fail: true)
    assert_nothing_raised { run_job(client: client, state: healthy_state, now: now) }
    refute_includes client.calls, :release
    assert_nil SolakonControlState.current.last_decision # unapplied decision is not remembered
  end

  test "relinquishes remote control after repeated failures" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 250, aenergy_wh: 1)
    client = FakeClient.new(fail: true)
    3.times { run_job(client: client, state: healthy_state, now: now) }
    assert_equal 1, client.calls.count(:release)
  end

  test "a success resets the failure counter" do
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 250, aenergy_wh: 1)

    failing = FakeClient.new(fail: true)
    2.times { run_job(client: failing, state: healthy_state, now: now) }   # 2 consecutive failures

    run_job(client: FakeClient.new, state: healthy_state, now: now) # success resets

    failing2 = FakeClient.new(fail: true)
    2.times { run_job(client: failing2, state: healthy_state, now: now) }  # only 2 again -> no release
    refute_includes failing2.calls, :release
  end

  test "no-op when runtime auto regulation is paused even if config permits control" do
    SolakonControlState.current.pause_auto_regulation!
    now = Time.zone.local(2026, 6, 20, 12, 0, 0)
    Sample.create!(plug_id: "fridge", ts: now.to_i - 5, apower_w: 250, aenergy_wh: 1)
    client = FakeClient.new

    run_job(client: client, state: healthy_state, now: now)

    assert_empty client.calls
  end
end
