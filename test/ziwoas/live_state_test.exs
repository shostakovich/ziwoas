defmodule Ziwoas.LiveStateTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Config, LiveState, Location, Repo}
  alias Ziwoas.Plugs.{Measurement, Plug}
  alias Ziwoas.Solakon.Reading

  @now DateTime.from_unix!(1_000_000_000_000, :microsecond)
  @now_ts 1_000_000

  defp plug(id, role), do: %Plug{id: id, name: String.upcase(id), role: role}

  defp solakon(monitoring_enabled \\ true),
    do: %Config.Solakon{
      host: "127.0.0.1",
      port: 502,
      unit_id: 1,
      monitoring_enabled: monitoring_enabled,
      control_enabled: false
    }

  defp config(opts \\ []) do
    %Config{
      location: Location.new("Europe/Berlin"),
      mqtt: nil,
      plugs:
        Keyword.get(opts, :plugs, [
          plug("bkw", :producer),
          plug("desk", :consumer),
          plug("heatpump", :consumer)
        ]),
      solakon: Keyword.get(opts, :solakon, solakon())
    }
  end

  defp live(opts \\ []), do: LiveState.build(config(), @now, opts)

  defp row(state, id), do: Enum.find(state.plugs, &(&1.id == id))

  defp sample(plug_id, age_s, watt), do: insert_sample!(plug_id, @now_ts - age_s, watt, 1.0)

  defp reading(age_s) do
    Repo.insert!(%Reading{
      taken_at: DateTime.add(@now, -age_s),
      active_power_w: 260.0,
      pv_power_w: 310.0,
      battery_power_w: 50.0,
      battery_soc_pct: 84
    })
  end

  test "a plug that never reported is offline and reports no watts" do
    desk = row(live(), "desk")

    assert desk.online == false
    assert desk.apower_w == nil
    assert desk.last_seen_ts == nil
  end

  test "a fresh plug is online with its watts; past the offline Frist it stays last seen" do
    sample("desk", 2, 342.5)
    sample("heatpump", 130, 80.0)
    state = live()

    assert %{online: true, apower_w: 342.5, last_seen_ts: 999_998} = row(state, "desk")
    assert %{online: false, apower_w: nil, last_seen_ts: 999_870} = row(state, "heatpump")
  end

  test "a plug line keeps the roster's role and name" do
    sample("bkw", 2, 1.0)
    assert %{role: :producer, name: "BKW"} = row(live(), "bkw")
  end

  test "a fresh reading puts the inverter online and splits the flow" do
    sample("desk", 2, 120.0)
    sample("heatpump", 2, 80.0)
    reading(2)

    flow = live().energy_flow

    assert flow.solakon_online
    assert flow.home_w == 200.0
    assert flow.solakon_ac_w == 260.0
    assert flow.solar_w == 310.0
    assert flow.battery_soc_pct == 84
    assert flow.battery_w == 50.0
    assert flow.battery_state == "charging"
    assert flow.grid_w == -60.0
    assert flow.flows.solar_to_battery_w == 50.0
  end

  test "the home figure sums only the consumer plugs that are online, never a producer" do
    sample("desk", 2, 120.0)
    sample("heatpump", 130, 80.0)
    sample("bkw", 2, 500.0)
    reading(2)

    state = live()
    assert state.energy_flow.home_w == 120.0
    assert state.energy_flow.grid_w == -140.0
  end

  test "a reading past the stale Frist leaves the inverter offline and every derived value unknown" do
    sample("desk", 2, 120.0)
    sample("heatpump", 2, 80.0)
    reading(121)

    flow = live().energy_flow

    assert flow.solakon_online == false
    assert flow.home_w == 200.0

    assert [flow.solakon_ac_w, flow.solar_w, flow.battery_soc_pct, flow.battery_w] == [
             nil,
             nil,
             nil,
             nil
           ]

    assert [flow.battery_state, flow.grid_w, flow.flows.solar_to_home_w] == [nil, nil, nil]
  end

  test "a reading exactly at the stale Frist is still fresh" do
    reading(120)
    assert live().energy_flow.solakon_online
  end

  test "monitoring switched off, or no inverter at all, leaves the inverter offline" do
    sample("desk", 2, 120.0)
    reading(2)

    for solakon <- [solakon(false), nil] do
      flow = LiveState.build(config(solakon: solakon), @now).energy_flow

      assert flow.solakon_online == false
      assert flow.home_w == 120.0
      assert flow.solar_w == nil
      assert flow.grid_w == nil
    end
  end

  test "an empty plug roster yields no plug lines and an unknown home figure" do
    state = LiveState.build(config(plugs: []), @now)

    assert state.plugs == []
    assert state.energy_flow.home_w == nil
  end

  test "both Fristen are injectable" do
    sample("desk", 130, 120.0)
    reading(130)

    state = live(offline_after_s: 200, stale_after_s: 200)

    assert row(state, "desk").online
    assert state.energy_flow.solakon_online
    assert state.energy_flow.home_w == 120.0
  end

  test "a fractional now is truncated to the whole second both Fristen are measured from" do
    sample("desk", Measurement.offline_after_s(), 120.0)

    state = LiveState.build(config(), DateTime.add(@now, 900_000, :microsecond))

    assert %{online: true, last_seen_ts: 999_880} = row(state, "desk")
  end
end
