require "test_helper"

class EnergyFlowTest < ActiveSupport::TestCase
  UNKNOWN_FLOWS = {
    solar_to_home_w: nil, solar_to_grid_w: nil, solar_to_battery_w: nil,
    grid_to_home_w: nil, grid_to_battery_w: nil, battery_to_home_w: nil
  }.freeze

  def reading(**attrs)
    SolakonReading.new({ taken_at: Time.current, active_power_w: 0, pv_power_w: 0,
                         battery_power_w: 0, battery_soc_pct: 50 }.merge(attrs))
  end

  test "surplus solar feeds the house, charges the battery and exports the rest" do
    flow = EnergyFlow.build(
      home_w: 200.0,
      reading: reading(active_power_w: 260, pv_power_w: 310, battery_power_w: 50, battery_soc_pct: 84)
    )

    assert_equal true, flow.solakon_online
    assert_in_delta 200.0, flow.home_w
    assert_in_delta 260.0, flow.solakon_ac_w
    assert_equal 84, flow.battery_soc_pct
    assert_equal "charging", flow.battery_state
    assert_in_delta(-60.0, flow.grid_w)
    assert_equal({
      solar_to_home_w: 200.0, solar_to_grid_w: 60.0, solar_to_battery_w: 50.0,
      grid_to_home_w: 0.0, grid_to_battery_w: 0.0, battery_to_home_w: 0.0
    }, flow.flows.to_h)
  end

  test "the grid reference corrects how much solar reached the battery" do
    flow = EnergyFlow.build(
      home_w: 200.0,
      reading: reading(active_power_w: 260, pv_power_w: 400, battery_power_w: 50, battery_soc_pct: 84)
    )

    assert_equal 200.0, flow.flows.solar_to_home_w
    assert_equal 60.0, flow.flows.solar_to_grid_w
    assert_equal 140.0, flow.flows.solar_to_battery_w
    assert_equal 0.0, flow.flows.battery_to_home_w
  end

  test "a discharging battery splits the house supply with solar and the grid" do
    flow = EnergyFlow.build(
      home_w: 200.0,
      reading: reading(active_power_w: 150, pv_power_w: 100, battery_power_w: -50, battery_soc_pct: 84)
    )

    assert_equal 100.0, flow.flows.solar_to_home_w
    assert_equal 0.0, flow.flows.solar_to_grid_w
    assert_equal 0.0, flow.flows.solar_to_battery_w
    assert_equal 50.0, flow.flows.grid_to_home_w
    assert_equal 50.0, flow.flows.battery_to_home_w
  end

  test "without a reading the inverter is offline and nothing is known" do
    flow = EnergyFlow.build(home_w: 200.0, reading: nil)

    assert_equal false, flow.solakon_online
    assert_nil flow.solakon_ac_w
    assert_nil flow.solar_w
    assert_nil flow.battery_soc_pct
    assert_nil flow.battery_state
    assert_nil flow.grid_w
    assert_equal UNKNOWN_FLOWS, flow.flows.to_h
  end

  test "an unknown house load leaves the grid and every flow unknown" do
    flow = EnergyFlow.build(
      home_w: nil,
      reading: reading(active_power_w: 260, pv_power_w: 310, battery_power_w: 50, battery_soc_pct: 84)
    )

    assert_equal true, flow.solakon_online
    assert_nil flow.home_w
    assert_in_delta 260.0, flow.solakon_ac_w
    assert_nil flow.grid_w
    assert_equal UNKNOWN_FLOWS, flow.flows.to_h
  end
end
