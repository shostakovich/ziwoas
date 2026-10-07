defmodule Ziwoas.Solakon.Control.PolicyTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Solakon.Control.{Decision, Load, Policy}
  alias Ziwoas.Solakon.Reading

  defp reading(attrs) do
    struct!(
      %Reading{
        battery_soc_pct: 50,
        pv_power_w: 0.0,
        battery_power_w: 0.0,
        battery_temperature_c: 25.0
      },
      attrs
    )
  end

  defp load(current_w, floor_w \\ 0.0), do: Load.new(current_w, floor_w)

  defp previous(state, target_w, trim \\ false),
    do: %Decision{state: state, target_w: target_w, trim: trim}

  defp decide(reading_attrs, load, previous \\ nil),
    do: Policy.decide(reading(reading_attrs), load, previous)

  defp outcome(decision), do: {decision.state, decision.target_w}

  describe "load following" do
    test "follows the measured load" do
      assert decide([], load(300.0)) == %Decision{state: :normal, target_w: 300, trim: false}
    end

    test "rises by at most 200 W per tick, falls at once" do
      assert outcome(decide([], load(600.0), previous(:normal, 100))) == {:normal, 300}
      assert outcome(decide([], load(200.0), previous(:normal, 500))) == {:normal, 200}
    end

    test "a previous target of 0 W still limits the rise" do
      assert outcome(decide([], load(600.0), previous(:normal, 0))) == {:normal, 200}
    end

    test "without a measured load the guaranteed floor stands in" do
      assert outcome(decide([], load(nil, 150.0))) == {:normal, 150}
    end

    test "a zero or negative load asks for nothing" do
      assert outcome(decide([], load(0.0))) == {:normal, 0}
      assert outcome(decide([], load(-50.0))) == {:normal, 0}
      assert outcome(decide([], load(nil, -20.0))) == {:normal, 0}
    end

    test "never asks for more than the inverter's 800 W" do
      assert outcome(decide([], load(1_200.0))) == {:normal, 800}
    end

    test "the target is whole watts, rounded" do
      assert outcome(decide([], load(299.5))) == {:normal, 300}
      assert outcome(decide([], load(299.4))) == {:normal, 299}
    end
  end

  describe "surplus control" do
    test "starts at 99 % while the battery charges beyond the deadband" do
      assert outcome(decide([battery_soc_pct: 99, battery_power_w: 100.0], load(300.0))) ==
               {:surplus, 300}
    end

    test "does not start below 99 % or inside the deadband" do
      assert outcome(decide([battery_soc_pct: 98, battery_power_w: 100.0], load(300.0))) ==
               {:normal, 300}

      assert outcome(decide([battery_soc_pct: 99, battery_power_w: 15.0], load(300.0))) ==
               {:normal, 300}
    end

    test "follows the battery's reaction: up to +200 W, down to −300 W, ±15 W deadband" do
      surplus = previous(:surplus, 500)
      full = [battery_soc_pct: 100, pv_power_w: 900.0]

      assert outcome(decide(full ++ [battery_power_w: 100.0], load(100.0), surplus)) ==
               {:surplus, 585}

      assert outcome(decide(full ++ [battery_power_w: 1_000.0], load(100.0), surplus)) ==
               {:surplus, 700}

      assert outcome(decide(full ++ [battery_power_w: 10.0], load(100.0), surplus)) ==
               {:surplus, 500}

      assert outcome(decide(full ++ [battery_power_w: -100.0], load(100.0), surplus)) ==
               {:surplus, 415}

      assert outcome(decide(full ++ [battery_power_w: -1_000.0], load(100.0), surplus)) ==
               {:surplus, 200}
    end

    test "never falls below load following" do
      decision =
        decide(
          [battery_soc_pct: 100, battery_power_w: -1_000.0],
          load(400.0),
          previous(:surplus, 500)
        )

      assert outcome(decision) == {:surplus_exhausted, 400}
    end

    test "is capped at 800 W" do
      decision =
        decide(
          [battery_soc_pct: 100, battery_power_w: 500.0],
          load(800.0),
          previous(:surplus, 750)
        )

      assert outcome(decision) == {:surplus, 800}
    end

    test "a discharging battery at the load-following floor exhausts it, a second discharging tick blocks probing" do
      exhausted =
        decide(
          [battery_soc_pct: 99, battery_power_w: -100.0],
          load(300.0),
          previous(:surplus, 300)
        )

      assert outcome(exhausted) == {:surplus_exhausted, 300}

      assert outcome(
               decide([battery_soc_pct: 99, battery_power_w: -100.0], load(300.0), exhausted)
             ) ==
               {:probe_blocked, 300}
    end

    test "an exhausted surplus resumes when the battery charges again, and holds while it idles" do
      exhausted = previous(:surplus_exhausted, 300)

      assert outcome(
               decide([battery_soc_pct: 99, battery_power_w: 100.0], load(300.0), exhausted)
             ) ==
               {:surplus, 385}

      assert outcome(decide([battery_soc_pct: 99, battery_power_w: 0.0], load(300.0), exhausted)) ==
               {:surplus_exhausted, 300}
    end

    test "ends when the SoC falls below 99 %" do
      for state <- [:surplus, :surplus_exhausted, :probe, :probe_blocked] do
        decision =
          decide([battery_soc_pct: 98, battery_power_w: 100.0], load(300.0), previous(state, 600))

        assert outcome(decision) == {:normal, 300}, "from #{state}"
      end
    end
  end

  describe "probe" do
    test "at 100 % without PV takes one 50 W step above load following" do
      assert outcome(decide([battery_soc_pct: 100], load(300.0))) == {:probe, 350}
    end

    test "is not taken with PV present or below 100 %" do
      assert outcome(decide([battery_soc_pct: 100, pv_power_w: 50.0], load(300.0))) ==
               {:normal, 300}

      assert outcome(decide([battery_soc_pct: 99], load(300.0))) == {:normal, 300}
    end

    test "at the output limit there is nothing to probe: it is blocked" do
      assert outcome(decide([battery_soc_pct: 100], load(800.0))) == {:probe_blocked, 800}
    end

    test "a discharging answer blocks further probes" do
      decision =
        decide(
          [battery_soc_pct: 100, battery_power_w: -100.0],
          load(300.0),
          previous(:probe, 350)
        )

      assert outcome(decision) == {:probe_blocked, 300}
    end

    test "a charging answer turns into surplus control from the probe's target" do
      decision =
        decide([battery_soc_pct: 100, battery_power_w: 100.0], load(300.0), previous(:probe, 350))

      assert outcome(decision) == {:surplus, 435}
    end

    test "a blocked probe stays blocked until charging shows again or the SoC falls" do
      blocked = previous(:probe_blocked, 300)

      assert outcome(decide([battery_soc_pct: 100], load(300.0), blocked)) ==
               {:probe_blocked, 300}

      assert outcome(decide([battery_soc_pct: 100, battery_power_w: 100.0], load(300.0), blocked)) ==
               {:surplus, 385}

      assert outcome(decide([battery_soc_pct: 98], load(300.0), blocked)) == {:normal, 300}
    end
  end

  describe "low-SoC trimming" do
    test "at 10 % enters at 85 % of what PV and load allow" do
      decision = decide([battery_soc_pct: 10, pv_power_w: 400.0], load(300.0))
      assert decision == %Decision{state: :protected, target_w: 255, trim: true}

      assert decide([battery_soc_pct: 10, pv_power_w: 200.0], load(300.0)).target_w == 170
    end

    test "then steers towards slight charging, within zero and the ceiling" do
      trimming = previous(:protected, 255, true)
      low = [battery_soc_pct: 10, pv_power_w: 400.0]

      assert decide(low ++ [battery_power_w: 45.0], load(300.0), trimming).target_w == 270
      assert decide(low ++ [battery_power_w: 15.0], load(300.0), trimming).target_w == 255
      assert decide(low ++ [battery_power_w: -45.0], load(300.0), trimming).target_w == 225
      assert decide(low ++ [battery_power_w: 500.0], load(300.0), trimming).target_w == 300
      assert decide(low ++ [battery_power_w: -1_000.0], load(300.0), trimming).target_w == 0
    end

    test "re-enters with the derating when the previous trim has no target" do
      decision =
        decide(
          [battery_soc_pct: 10, pv_power_w: 400.0, battery_power_w: 45.0],
          load(300.0),
          previous(:protected, nil, true)
        )

      assert decision.target_w == 255
    end

    test "gives nothing without PV, and nothing for a zero or negative load" do
      assert decide([battery_soc_pct: 5], load(300.0)).target_w == 0
      assert decide([battery_soc_pct: 5, pv_power_w: 400.0], load(0.0)).target_w == 0
      assert decide([battery_soc_pct: 5, pv_power_w: 400.0], load(-100.0)).target_w == 0

      trimming = previous(:protected, 200, true)

      assert decide([battery_soc_pct: 5, pv_power_w: 400.0], load(-100.0), trimming).target_w ==
               0
    end

    test "uses the floor without a measured load" do
      assert decide([battery_soc_pct: 10, pv_power_w: 400.0], load(nil, 200.0)).target_w == 170
    end

    test "holds through 10 % and ends at 11 %" do
      trimming = previous(:protected, 255, true)

      assert decide([battery_soc_pct: 10, pv_power_w: 400.0], load(300.0), trimming).state ==
               :protected

      assert decide([battery_soc_pct: 11, pv_power_w: 400.0], load(300.0), trimming) ==
               %Decision{state: :normal, target_w: 300, trim: false}
    end

    test "11 % without a previous protection is no protection" do
      assert outcome(decide([battery_soc_pct: 11], load(300.0))) == {:normal, 300}
    end

    test "protection wins over surplus and probe" do
      assert decide([battery_soc_pct: 10, battery_power_w: 200.0], load(300.0)).state ==
               :protected

      assert decide([battery_soc_pct: 0], load(300.0), previous(:surplus, 600)).state ==
               :protected
    end
  end

  describe "heat derating" do
    test "the ceiling falls linearly from 800 W at 45 °C to 0 W at 49 °C" do
      ceiling = fn temp -> Policy.thermal_ceiling_w(reading(battery_temperature_c: temp)) end

      assert ceiling.(44.9) == 800
      assert ceiling.(45.0) == 800
      assert ceiling.(47.0) == 400
      assert ceiling.(48.0) == 200
      assert ceiling.(49.0) == 0
      assert ceiling.(55.0) == 0
      assert ceiling.(nil) == 800
    end

    test "a hot battery follows the load below the ceiling" do
      assert decide([battery_temperature_c: 47.0], load(300.0)) ==
               %Decision{state: :protected, target_w: 300, trim: false}

      assert decide([battery_temperature_c: 47.0], load(600.0)).target_w == 400
      assert decide([battery_temperature_c: 49.5], load(600.0)).target_w == 0
    end

    test "heat wins over surplus control" do
      decision =
        decide(
          [battery_soc_pct: 100, battery_power_w: 300.0, battery_temperature_c: 48.0],
          load(500.0),
          previous(:surplus, 700)
        )

      assert outcome(decision) == {:protected, 200}
    end

    test "heat and a low SoC: the trim, capped by the heat ceiling" do
      decision =
        decide([battery_soc_pct: 8, pv_power_w: 800.0, battery_temperature_c: 47.0], load(700.0))

      assert decision == %Decision{state: :protected, target_w: 400, trim: true}
    end

    test "protection lasts until the battery has cooled below 45 °C" do
      hot = previous(:protected, 300)

      assert decide([battery_temperature_c: 45.0], load(300.0), hot).state == :protected
      assert decide([battery_temperature_c: 44.9], load(300.0), hot).state == :normal
    end

    test "a missing temperature counts as cool" do
      assert decide([battery_temperature_c: nil], load(300.0)).state == :normal
    end
  end

  test "missing power figures read as 0 W" do
    assert outcome(
             decide([battery_soc_pct: 100, pv_power_w: nil, battery_power_w: nil], load(300.0))
           ) ==
             {:probe, 350}
  end
end
