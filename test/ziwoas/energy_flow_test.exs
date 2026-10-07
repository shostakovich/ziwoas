defmodule Ziwoas.EnergyFlowTest do
  use ExUnit.Case, async: true

  alias Ziwoas.EnergyFlow
  alias Ziwoas.EnergyFlow.Flows
  alias Ziwoas.Solakon.Reading

  @unknown %Flows{}

  defp reading(attrs) do
    struct!(
      %Reading{active_power_w: 0.0, pv_power_w: 0.0, battery_power_w: 0.0, battery_soc_pct: 50},
      attrs
    )
  end

  defp flows(flow), do: Map.from_struct(flow)

  defp split(home, solar, battery, grid), do: flows(Flows.split(home, solar, battery, grid))

  defp expected(values) do
    Enum.zip(Flows.keys(), values) |> Map.new()
  end

  test "surplus solar feeds the house, charges the battery and exports the rest" do
    flow =
      EnergyFlow.build(
        200.0,
        reading(
          active_power_w: 260.0,
          pv_power_w: 310.0,
          battery_power_w: 50.0,
          battery_soc_pct: 84
        )
      )

    assert flow.solakon_online == true
    assert flow.home_w == 200.0
    assert flow.solakon_ac_w == 260.0
    assert flow.battery_soc_pct == 84
    assert flow.battery_state == "charging"
    assert flow.grid_w == -60.0
    assert flow.solar_w == 310.0
    assert flow.battery_w == 50.0
    assert flows(flow.flows) == expected([200.0, 60.0, 50.0, 0.0, 0.0, 0.0])
  end

  test "the grid reference corrects how much solar reached the battery" do
    flow =
      EnergyFlow.build(
        200.0,
        reading(
          active_power_w: 260.0,
          pv_power_w: 400.0,
          battery_power_w: 50.0,
          battery_soc_pct: 84
        )
      )

    assert flow.flows.solar_to_home_w == 200.0
    assert flow.flows.solar_to_grid_w == 60.0
    assert flow.flows.solar_to_battery_w == 140.0
    assert flow.flows.battery_to_home_w == 0.0
  end

  test "a discharging battery splits the house supply with solar and the grid" do
    flow =
      EnergyFlow.build(
        200.0,
        reading(
          active_power_w: 150.0,
          pv_power_w: 100.0,
          battery_power_w: -50.0,
          battery_soc_pct: 84
        )
      )

    assert flows(flow.flows) == expected([100.0, 0.0, 0.0, 50.0, 0.0, 50.0])
  end

  test "without a reading the inverter is offline and nothing is known" do
    flow = EnergyFlow.build(200.0, nil)

    assert flow.solakon_online == false

    assert {flow.solakon_ac_w, flow.solar_w, flow.battery_soc_pct, flow.battery_state,
            flow.grid_w} ==
             {nil, nil, nil, nil, nil}

    assert flow.flows == @unknown
  end

  test "an unknown house load leaves the grid and every flow unknown" do
    flow =
      EnergyFlow.build(
        nil,
        reading(
          active_power_w: 260.0,
          pv_power_w: 310.0,
          battery_power_w: 50.0,
          battery_soc_pct: 84
        )
      )

    assert flow.solakon_online == true
    assert flow.home_w == nil
    assert flow.solakon_ac_w == 260.0
    assert flow.grid_w == nil
    assert flow.flows == @unknown
  end

  test "Flows.split treats any one nil input as unknown" do
    assert Flows.split(nil, 10.0, 1.0, 1.0) == @unknown
    assert Flows.split(10.0, nil, 1.0, 1.0) == @unknown
    assert Flows.split(10.0, 10.0, nil, 1.0) == @unknown
    assert Flows.split(10.0, 10.0, 1.0, nil) == @unknown
  end

  test "Flows.split rounds every watt figure to one decimal" do
    assert split(123.37, 300.29, 40.71, -50.13) == expected([123.4, 50.1, 126.8, 0.0, 0.0, 0.0])
    assert split(205.83, 60.47, -53.29, 92.19) == expected([60.5, 0.0, 0.0, 92.2, 0.0, 53.2])
  end

  test "the grid tops up the battery once solar alone cannot, up to the tighter limit" do
    assert split(80.23, 15.61, 90.38, 150.77) == expected([0.0, 0.0, 15.6, 80.2, 70.5, 0.0])
    assert split(80.23, 15.61, 50.19, 200.94) == expected([0.0, 0.0, 15.6, 80.2, 34.6, 0.0])
  end

  test "edge cases of the split" do
    assert split(100.37, 50.0, 1.0, 100.0) == expected([0.4, 0.0, 49.6, 100.0, 0.0, 0.0])
    assert split(5.0, 10.0, 1.0, -50.0) == expected([0.0, 50.0, 0.0, 0.0, 0.0, 0.0])
    assert split(200.0, 0.0, -10.0, 50.0) == expected([0.0, 0.0, 0.0, 50.0, 0.0, 10.0])
    assert split(50.0, 100.0, 5.0, 80.0) == expected([0.0, 0.0, 100.0, 50.0, 0.0, 0.0])
    assert split(-10.0, 5.0, 3.0, 2.0) == expected([0.0, 0.0, 5.0, 0.0, 0.0, 0.0])
    assert split(50.0, -5.0, 2.0, 3.0) == expected([0.0, 0.0, 0.0, 3.0, 0.0, 0.0])
  end

  test "an idle battery sends nothing to the house, not a negative zero" do
    flow =
      EnergyFlow.build(
        1.3,
        reading(active_power_w: 642.4, pv_power_w: 669.1, battery_soc_pct: 100)
      )

    assert flow.flows.battery_to_home_w === 0.0

    assert JSON.decode!(EnergyFlow.to_json(flow)) == %{
             "solakon_online" => true,
             "home_w" => 1.3,
             "solakon_ac_w" => 642.4,
             "solar_w" => 669.1,
             "battery_soc_pct" => 100,
             "battery_w" => 0.0,
             "battery_state" => "normal",
             "grid_w" => -641.1,
             "flows" => %{
               "solar_to_home_w" => 1.3,
               "solar_to_grid_w" => 641.1,
               "solar_to_battery_w" => 0.0,
               "grid_to_home_w" => 0.0,
               "grid_to_battery_w" => 0.0,
               "battery_to_home_w" => 0.0
             }
           }
  end

  test "an unknown flow serialises its unknowns as null" do
    json = JSON.decode!(EnergyFlow.to_json(EnergyFlow.build(nil, nil)))

    assert json["solakon_online"] == false
    assert json["home_w"] == nil
    assert Map.values(json["flows"]) == List.duplicate(nil, 6)
  end

  test "integer inputs come out as floats" do
    flow = EnergyFlow.build(200, reading(active_power_w: 150, pv_power_w: 100))

    assert flow.home_w === 200.0
    assert flow.grid_w === 50.0
    assert flow.flows.solar_to_home_w === 100.0
  end
end
