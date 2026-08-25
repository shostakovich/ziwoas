require "test_helper"

class LiveStateTest < ActiveSupport::TestCase
  cover "LiveState*"

  NOW = Time.zone.at(1_000_000)

  setup do
    Plugs::Sample.delete_all
    SolakonReading.delete_all
  end

  test "a plug that never reported is offline and reports no watts" do
    row = LiveState::Row.build(plug("desk", :consumer), measurement("desk"))

    assert_equal false, row.online
    assert_nil row.apower_w
    assert_nil row.last_seen_ts
  end

  test "a plug with a fresh measurement is online and reports the watts it measured" do
    row = LiveState::Row.build(plug("desk", :consumer), measurement("desk", age_s: 2, watt: 342.5))

    assert_equal true, row.online
    assert_in_delta 342.5, row.apower_w
    assert_equal NOW.to_i - 2, row.last_seen_ts
  end

  test "a plug goes offline once its newest measurement outlives the offline Frist, but stays last seen" do
    row = LiveState::Row.build(plug("desk", :consumer), measurement("desk", age_s: 130, watt: 80.0))

    assert_equal false, row.online
    assert_nil row.apower_w
    assert_equal NOW.to_i - 130, row.last_seen_ts
  end

  test "a plug line keeps the role as the symbol the roster speaks" do
    row = LiveState::Row.build(plug("bkw", :producer), measurement("bkw", age_s: 2, watt: 1.0))

    assert_equal :producer, row.role
    assert_equal "BKW", row.name
  end

  test "a fresh reading puts the inverter online and splits the flow between solar, battery and grid" do
    sample("desk", 2, 120.0)
    sample("heatpump", 2, 80.0)
    reading(2)

    flow = live.energy_flow

    assert_equal true, flow.solakon_online
    assert_in_delta 200.0, flow.home_w
    assert_in_delta 260.0, flow.solakon_ac_w
    assert_in_delta 310.0, flow.solar_w
    assert_equal 84, flow.battery_soc_pct
    assert_in_delta 50.0, flow.battery_w
    assert_equal "charging", flow.battery_state
    assert_in_delta(-60.0, flow.grid_w)
    assert_equal({ solar_to_home_w: 200.0, solar_to_grid_w: 60.0, solar_to_battery_w: 50.0,
                   grid_to_home_w: 0.0, grid_to_battery_w: 0.0, battery_to_home_w: 0.0 },
                 flow.flows.to_h)
  end

  test "the home figure sums only the consumer plugs that are not offline" do
    sample("desk", 2, 120.0)
    sample("heatpump", 130, 80.0)
    reading(2)

    state = live

    assert_in_delta 120.0, state.energy_flow.home_w
    assert_in_delta(-140.0, state.energy_flow.grid_w)
    assert_equal false, state.plugs.find { |row| row.id == "heatpump" }.online
  end

  test "the home figure never counts a producer, online or offline" do
    sample("desk", 2, 120.0)
    sample("bkw", 2, 500.0)

    assert_in_delta 120.0, live.energy_flow.home_w

    Plugs::Sample.delete_all
    sample("desk", 2, 120.0)
    sample("bkw", 130, 500.0)

    assert_in_delta 120.0, live.energy_flow.home_w
  end

  test "a reading past the stale Frist leaves the inverter offline and every derived value unknown" do
    sample("desk", 2, 120.0)
    sample("heatpump", 2, 80.0)
    reading(121)

    flow = live.energy_flow

    assert_equal false, flow.solakon_online
    assert_in_delta 200.0, flow.home_w
    assert_nil flow.solakon_ac_w
    assert_nil flow.solar_w
    assert_nil flow.battery_soc_pct
    assert_nil flow.battery_w
    assert_nil flow.battery_state
    assert_nil flow.grid_w
    assert_equal({ solar_to_home_w: nil, solar_to_grid_w: nil, solar_to_battery_w: nil,
                   grid_to_home_w: nil, grid_to_battery_w: nil, battery_to_home_w: nil },
                 flow.flows.to_h)
  end

  test "monitoring switched off leaves the inverter offline without ever asking for a reading" do
    sample("desk", 2, 120.0)
    reading(2)

    flow = LiveState.for(config: config(solakon: solakon_cfg(monitoring_enabled: false)),
                         now: NOW).energy_flow

    assert_equal false, flow.solakon_online
    assert_in_delta 120.0, flow.home_w
    assert_nil flow.solar_w
    assert_nil flow.grid_w
  end

  test "with no inverter configured at all the flow is unknown, not zero" do
    sample("desk", 2, 120.0)

    flow = LiveState.for(config: config(solakon: nil), now: NOW).energy_flow

    assert_equal false, flow.solakon_online
    assert_in_delta 120.0, flow.home_w
    assert_nil flow.solar_w
  end

  test "an empty plug roster yields no plug lines and an unknown home figure" do
    state = LiveState.for(config: config(plugs: []), now: NOW)

    assert_empty state.plugs
    assert_nil state.energy_flow.home_w
  end

  test "both Fristen are injectable, so a caller can widen them without touching the models" do
    sample("desk", 130, 120.0)
    reading(130)

    state = live(offline_after_s: 200, stale_after_s: 200)

    assert_equal true, state.plugs.find { |row| row.id == "desk" }.online
    assert_equal true, state.energy_flow.solakon_online
    assert_in_delta 120.0, state.energy_flow.home_w
  end

  test "a fractional now is truncated to the whole second both Fristen are measured from" do
    sample("desk", 2, 120.0)

    state = LiveState.for(config: config, now: Time.zone.at(NOW.to_i + 0.75))

    assert_equal NOW.to_i - 2, state.plugs.find { |row| row.id == "desk" }.last_seen_ts
  end

  test "a fractional now does not push a plug past the offline Frist early" do
    sample("desk", Plugs::Measurement::OFFLINE_AFTER_S, 120.0)

    state = LiveState.for(config: config, now: Time.zone.at(NOW.to_i + 0.9))

    assert_equal true, state.plugs.find { |row| row.id == "desk" }.online
  end

  test "an update names a plug the way a row does, and dates it the same way" do
    update = LiveState::Update.new(id: "desk", name: "DESK", role: :consumer, apower_w: 120.0,
                                   last_seen_ts: NOW.to_i, bucket_ts: NOW.to_i - 20,
                                   avg_power_w: -110.0, output: true)

    assert_empty LiveState::Row.attribute_names - [ :online ] - LiveState::Update.attribute_names
    assert_equal({ id: "desk", name: "DESK", role: :consumer, apower_w: 120.0,
                   last_seen_ts: NOW.to_i, bucket_ts: NOW.to_i - 20,
                   avg_power_w: -110.0, output: true }, update.to_h)
  end

  test "an update carries no online flag: it dates the report and leaves the Frist to the reader" do
    refute_includes LiveState::Update.attribute_names, :online
  end

  test "an update tolerates a plug that reports no output and no bucket yet" do
    update = LiveState::Update.new(id: "desk", name: "DESK", role: :consumer, apower_w: nil,
                                   last_seen_ts: nil, bucket_ts: nil, avg_power_w: nil, output: nil)

    assert_nil update.output
    assert_nil update.last_seen_ts
  end

  test "with no now given, live state measures from the actual current time" do
    travel_to NOW do
      sample("desk", 2, 120.0)

      state = LiveState.for(config: config)

      assert_equal NOW.to_i - 2, state.plugs.find { |row| row.id == "desk" }.last_seen_ts
    end
  end

  private

  def plug(id, role) = ConfigLoader::PlugCfg.new(id: id, name: id.upcase, role: role, driver: :shelly)

  def measurement(plug_id, age_s: nil, watt: nil)
    Plugs::Measurement.new(plug_id: plug_id, watt: watt,
                           last_seen_at: age_s && (NOW - age_s),
                           now: NOW, offline_after_s: Plugs::Measurement::OFFLINE_AFTER_S)
  end

  def solakon_cfg(monitoring_enabled: true)
    ConfigLoader::SolakonCfg.new(host: "127.0.0.1", port: 502, unit_id: 1,
                                 monitoring_enabled: monitoring_enabled, control_enabled: false)
  end

  def config(plugs: default_plugs, solakon: solakon_cfg)
    ConfigLoader::Config.new(electricity_price_eur_per_kwh: 0.32, timezone: "Europe/Berlin",
                             plugs: plugs, sensors: [], solakon: solakon)
  end

  def default_plugs
    [ plug("bkw", :producer), plug("desk", :consumer), plug("heatpump", :consumer) ]
  end

  def live(**kwargs) = LiveState.for(config: config, now: NOW, **kwargs)

  def sample(plug_id, age_s, watt)
    Plugs::Sample.create!(plug_id: plug_id, ts: NOW.to_i - age_s, apower_w: watt, aenergy_wh: 1.0)
  end

  def reading(age_s)
    SolakonReading.create!(taken_at: NOW - age_s, active_power_w: 260, pv_power_w: 310,
                           battery_power_w: 50, battery_soc_pct: 84)
  end
end
