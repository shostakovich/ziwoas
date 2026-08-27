require "test_helper"

class EnergyFlowTest < ActiveSupport::TestCase
  cover "EnergyFlow*"

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

  test "solar and battery power come from the reading, not from the split" do
    flow = EnergyFlow.build(
      home_w: 200.0,
      reading: reading(active_power_w: 260, pv_power_w: 310, battery_power_w: 50, battery_soc_pct: 84)
    )

    assert_in_delta 310.0, flow.solar_w
    assert_in_delta 50.0, flow.battery_w
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

  # EnergyFlow::Flows.split exercised directly: it lets each of the four inputs
  # go missing independently, something EnergyFlow.build's own nil-propagation
  # (home_w and grid_w always turn nil together) can never isolate.
  test "Flows.split treats a nil home_w alone as unknown, not only when it drags grid_w along" do
    flow = EnergyFlow::Flows.split(home_w: nil, solar_w: 10.0, battery_w: 1.0, grid_w: 1.0)

    assert_equal UNKNOWN_FLOWS, flow.to_h
  end

  test "Flows.split treats a nil solar_w alone as unknown" do
    flow = EnergyFlow::Flows.split(home_w: 10.0, solar_w: nil, battery_w: 1.0, grid_w: 1.0)

    assert_equal UNKNOWN_FLOWS, flow.to_h
  end

  test "Flows.split treats a nil battery_w alone as unknown" do
    flow = EnergyFlow::Flows.split(home_w: 10.0, solar_w: 10.0, battery_w: nil, grid_w: 1.0)

    assert_equal UNKNOWN_FLOWS, flow.to_h
  end

  test "Flows.split treats a nil grid_w alone as unknown" do
    flow = EnergyFlow::Flows.split(home_w: 10.0, solar_w: 10.0, battery_w: 1.0, grid_w: nil)

    assert_equal UNKNOWN_FLOWS, flow.to_h
  end

  test "Flows.split rounds every watt figure to one decimal, not zero, two or more" do
    flow = EnergyFlow::Flows.split(home_w: 123.37, solar_w: 300.29, battery_w: 40.71, grid_w: -50.13)

    assert_equal({
      solar_to_home_w: 123.4, solar_to_grid_w: 50.1, solar_to_battery_w: 126.8,
      grid_to_home_w: 0.0, grid_to_battery_w: 0.0, battery_to_home_w: 0.0
    }, flow.to_h)
  end

  test "a discharging battery with import and export in play still rounds to one decimal" do
    flow = EnergyFlow::Flows.split(home_w: 205.83, solar_w: 60.47, battery_w: -53.29, grid_w: 92.19)

    assert_equal({
      solar_to_home_w: 60.5, solar_to_grid_w: 0.0, solar_to_battery_w: 0.0,
      grid_to_home_w: 92.2, grid_to_battery_w: 0.0, battery_to_home_w: 53.2
    }, flow.to_h)
  end

  test "the grid tops up the battery once solar alone cannot, when the grid headroom is the tighter limit" do
    flow = EnergyFlow::Flows.split(home_w: 80.23, solar_w: 15.61, battery_w: 90.38, grid_w: 150.77)

    assert_equal({
      solar_to_home_w: 0.0, solar_to_grid_w: 0.0, solar_to_battery_w: 15.6,
      grid_to_home_w: 80.2, grid_to_battery_w: 70.5, battery_to_home_w: 0.0
    }, flow.to_h)
  end

  test "the grid tops up the battery only up to what the battery still needs, when that is the tighter limit" do
    flow = EnergyFlow::Flows.split(home_w: 80.23, solar_w: 15.61, battery_w: 50.19, grid_w: 200.94)

    assert_equal({
      solar_to_home_w: 0.0, solar_to_grid_w: 0.0, solar_to_battery_w: 15.6,
      grid_to_home_w: 80.2, grid_to_battery_w: 34.6, battery_to_home_w: 0.0
    }, flow.to_h)
  end

  test "a home remainder under one watt is not rounded up to a whole watt before the split" do
    flow = EnergyFlow::Flows.split(home_w: 100.37, solar_w: 50.0, battery_w: 1.0, grid_w: 100.0)

    assert_equal({
      solar_to_home_w: 0.4, solar_to_grid_w: 0.0, solar_to_battery_w: 49.6,
      grid_to_home_w: 100.0, grid_to_battery_w: 0.0, battery_to_home_w: 0.0
    }, flow.to_h)
  end

  test "solar production too small for the export it is charged with leaves nothing for the house or battery" do
    flow = EnergyFlow::Flows.split(home_w: 5.0, solar_w: 10.0, battery_w: 1.0, grid_w: -50.0)

    assert_equal({
      solar_to_home_w: 0.0, solar_to_grid_w: 50.0, solar_to_battery_w: 0.0,
      grid_to_home_w: 0.0, grid_to_battery_w: 0.0, battery_to_home_w: 0.0
    }, flow.to_h)
  end

  test "a small battery discharge is capped by the battery itself, not by what the house still needs" do
    flow = EnergyFlow::Flows.split(home_w: 200.0, solar_w: 0.0, battery_w: -10.0, grid_w: 50.0)

    assert_equal({
      solar_to_home_w: 0.0, solar_to_grid_w: 0.0, solar_to_battery_w: 0.0,
      grid_to_home_w: 50.0, grid_to_battery_w: 0.0, battery_to_home_w: 10.0
    }, flow.to_h)
  end

  test "solar that already covers the battery's whole need leaves no room for the grid to add more" do
    flow = EnergyFlow::Flows.split(home_w: 50.0, solar_w: 100.0, battery_w: 5.0, grid_w: 80.0)

    assert_equal({
      solar_to_home_w: 0.0, solar_to_grid_w: 0.0, solar_to_battery_w: 100.0,
      grid_to_home_w: 50.0, grid_to_battery_w: 0.0, battery_to_home_w: 0.0
    }, flow.to_h)
  end

  test "a negative home_w is clamped to zero rather than eating into the grid supply" do
    flow = EnergyFlow::Flows.split(home_w: -10.0, solar_w: 5.0, battery_w: 3.0, grid_w: 2.0)

    assert_equal({
      solar_to_home_w: 0.0, solar_to_grid_w: 0.0, solar_to_battery_w: 5.0,
      grid_to_home_w: 0.0, grid_to_battery_w: 0.0, battery_to_home_w: 0.0
    }, flow.to_h)
  end

  test "a negative solar_w is clamped to zero rather than shrinking what the grid covers" do
    flow = EnergyFlow::Flows.split(home_w: 50.0, solar_w: -5.0, battery_w: 2.0, grid_w: 3.0)

    assert_equal({
      solar_to_home_w: 0.0, solar_to_grid_w: 0.0, solar_to_battery_w: 0.0,
      grid_to_home_w: 3.0, grid_to_battery_w: 0.0, battery_to_home_w: 0.0
    }, flow.to_h)
  end
end
