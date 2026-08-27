require "test_helper"

# module_function gives DashboardBroadcaster.broadcast_live etc. a *snapshot*
# singleton method, taken once when the file first loads. Mutant's killfork
# monkeypatches only the instance-method-table entry (undef + redefine), so a
# call through the module method never runs the mutated body — every mutation
# looks alive no matter what the test asserts. Routing calls through an
# includer reaches the entry mutant actually rewrites.
class DashboardBroadcasterCaller
  include DashboardBroadcaster
end

class DashboardBroadcasterTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  cover "DashboardBroadcaster*"

  setup do
    Plugs::Sample.delete_all
    Plugs::State.delete_all
    Plugs::DailyTotal.delete_all
    SolakonReading.delete_all
    WeatherRecord.delete_all
  end

  test "broadcast_live replaces hero, live tiles, plug bar and the flow carrier" do
    now = Time.now.to_i
    Plugs::Sample.create!(plug_id: "bkw", ts: now - 2, apower_w: -420.0, aenergy_wh: 1000.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: now - 2, apower_w: 80.0, aenergy_wh: 500.0)

    payloads = capture_payloads { broadcast_live }

    assert_replace_for "dashboard_hero", payloads
    assert_replace_for "tile_consumption_now", payloads
    assert_replace_for "tile_netbalance_now", payloads
    assert_replace_for "dashboard_plug_bar", payloads
    assert_replace_for "energy_flow_state", payloads

    assert_match(/alt="Sonne"/, payload_for("dashboard_hero", payloads))

    consumption = payload_for("tile_consumption_now", payloads)
    assert_match(/80 W/, consumption)
    refute_match(/app-header/, consumption, "a fragment must not ship the page layout")
  end

  test "broadcast_live renders the switch head for every switchable plug" do
    payloads = capture_payloads { broadcast_live }

    assert_replace_for "sw_head_fridge", payloads
    refute payloads.any? { |p| p.include?(%(target="sw_head_bkw")) },
           "bkw is not switchable and must not get a head broadcast"
  end

  test "broadcast_live ships plug deltas only when there are any" do
    delta = LiveState::Update.new(
      id: "fridge", name: "Kühlschrank", role: :consumer,
      apower_w: 80.0, last_seen_ts: 1_700_000_000,
      bucket_ts: 1_699_999_980, avg_power_w: 78.5, output: nil
    )

    without = capture_payloads { broadcast_live }
    refute without.any? { |p| p.include?(%(target="plug_deltas")) }

    with = capture_payloads { broadcast_live(deltas: [ delta ]) }
    assert_replace_for "plug_deltas", with
    assert_match(/avg_power_w/, payload_for("plug_deltas", with))
  end

  test "broadcast_switch_heads broadcasts nothing when no plug is switchable" do
    config = Struct.new(:plugs).new([
      ConfigLoader::PlugCfg.new(id: "bkw", name: "Balkonkraftwerk", role: :producer, switchable: false)
    ])

    payloads = capture_payloads { DashboardBroadcasterCaller.new.send(:broadcast_switch_heads, config) }

    assert_empty payloads
  end

  test "broadcast_summary replaces the six day tiles with computed values" do
    payloads = capture_payloads { broadcast_summary }

    %w[tile_produced tile_consumed tile_savings tile_net_today
       tile_autarky tile_self_consumption].each do |target|
      assert_replace_for target, payloads
    end
    assert_match(/0,00 kWh/, payload_for("tile_produced", payloads))
  end

  private

  def broadcast_live(**args) = DashboardBroadcasterCaller.new.send(:broadcast_live, **args)
  def broadcast_summary(**args) = DashboardBroadcasterCaller.new.send(:broadcast_summary, **args)

  def capture_payloads(&block)
    block.call
    broadcasts(DashboardBroadcaster::STREAM).map { |raw| JSON.parse(raw) }
  end

  def assert_replace_for(target, payloads)
    assert payload_for(target, payloads),
           "expected a turbo-stream replace for #{target} in #{payloads.inspect}"
  end

  def payload_for(target, payloads)
    payloads.find { |p| p.include?(%(target="#{target}")) && p.include?(%(action="replace")) }
  end
end
