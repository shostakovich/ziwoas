defmodule Ziwoas.Solakon.Control.Policy do
  @moduledoc """
  The control's state machine (Rails' `Solakon::Control::Policy`, ADR-0002): from a
  reading, the household load and the previous decision to the next target.

    * **Load following**: the measured load (else the guaranteed floor), rising by at
      most 200 W per tick, falling at once.
    * **Surplus control** from 99 % SoC while the battery charges: the target follows
      the battery's reaction (+200 W / −300 W per tick, ±15 W deadband), never below
      the load-following target; two discharging ticks there end it.
    * **Probe**: at 100 % with PV under 50 W, one 50 W step; a discharging answer
      blocks further probes until SoC falls below 99 % or charging shows again.
    * **Protection** wins over everything: at or below 10 % SoC the target trims
      towards slight charging within PV and load; from 45 °C a linear thermal
      ceiling falls to zero at 49 °C.

  Pure: `test/vectors/solakon_policy.json` pins it against Rails. Numbers follow
  Ruby's (`nil.to_f` is 0.0, the target rounds half away from zero). A negative
  measured load while trimming makes Rails' `Comparable#clamp` raise; so does this.
  """
  alias Ziwoas.RubyNumeric
  alias Ziwoas.Solakon.Control.{Decision, Load}
  alias Ziwoas.Solakon.Reading

  @max_output_w 800
  @hot_output_limit_w 800
  @normal_rise_limit_w 200
  @surplus_rise_limit_w 200
  @surplus_fall_limit_w 300
  @surplus_soc_pct 99
  @full_soc_pct 100
  @surplus_deadband_w 15
  @probe_step_w 50
  # Below resume SoC the trim aims for slight charging, not neutral, so conversion
  # losses can never bleed the SoC under 10 %.
  @charge_bias_w 15
  @trim_gain 0.5
  @entry_derate 0.85

  def max_output_w, do: @max_output_w

  @spec decide(Reading.t(), Load.t(), Decision.t() | nil) :: Decision.t()
  def decide(%Reading{} = reading, %Load{} = load, previous \\ nil) do
    {state, raw} =
      if protecting?(reading, previous && previous.state),
        do: {:protected, protected_target(reading, load, previous)},
        else: unprotected_decision(reading, load, previous)

    target =
      [RubyNumeric.to_f(raw), thermal_ceiling_w(reading)]
      |> Enum.min()
      |> clamp(0.0, @max_output_w)
      |> round()

    %Decision{
      state: state,
      target_w: target,
      trim: state == :protected and not Reading.soc_at_resume?(reading)
    }
  end

  @doc false
  def protecting?(reading, previous_state) do
    cond do
      Reading.soc_below_minimum?(reading) or Reading.battery_hot?(reading) -> true
      previous_state != :protected -> false
      true -> not (Reading.soc_at_resume?(reading) and Reading.battery_cooled?(reading))
    end
  end

  defp unprotected_decision(reading, load, previous) do
    baseline = normal_target(load, previous)

    case previous && previous.state do
      :surplus -> continue_surplus(reading, baseline, previous)
      :surplus_exhausted -> continue_surplus_exit(reading, baseline, previous)
      :probe -> resolve_probe(reading, baseline, previous)
      :probe_blocked -> continue_probe_block(reading, baseline, previous)
      _ -> start_unprotected_mode(reading, baseline, previous)
    end
  end

  @doc false
  def normal_target(load, previous) do
    demand = load |> Load.effective_w() |> RubyNumeric.to_f()

    case target_of(previous) do
      nil -> demand
      target -> min(demand, target + @normal_rise_limit_w)
    end
  end

  defp start_unprotected_mode(reading, baseline, previous) do
    cond do
      surplus_available?(reading) ->
        surplus_decision(reading, baseline, previous)

      probe_candidate?(reading, baseline) ->
        {:probe, baseline + @probe_step_w}

      soc(reading) >= @full_soc_pct and not Reading.pv_present?(reading) ->
        {:probe_blocked, baseline}

      true ->
        {:normal, baseline}
    end
  end

  defp continue_surplus(reading, baseline, previous) do
    if soc(reading) < @surplus_soc_pct,
      do: {:normal, baseline},
      else: surplus_decision(reading, baseline, previous)
  end

  defp continue_surplus_exit(reading, baseline, previous) do
    cond do
      soc(reading) < @surplus_soc_pct -> {:normal, baseline}
      charging_surplus?(reading) -> surplus_decision(reading, baseline, previous)
      battery_discharging?(reading) -> {:probe_blocked, baseline}
      true -> {:surplus_exhausted, baseline}
    end
  end

  defp resolve_probe(reading, baseline, previous) do
    cond do
      soc(reading) < @surplus_soc_pct -> {:normal, baseline}
      battery_discharging?(reading) -> {:probe_blocked, baseline}
      true -> surplus_decision(reading, baseline, previous)
    end
  end

  defp continue_probe_block(reading, baseline, previous) do
    cond do
      soc(reading) < @surplus_soc_pct -> {:normal, baseline}
      charging_surplus?(reading) -> surplus_decision(reading, baseline, previous)
      true -> {:probe_blocked, baseline}
    end
  end

  defp surplus_decision(reading, baseline, previous) do
    target = surplus_target(reading, baseline, previous)

    if battery_discharging?(reading) and target <= baseline,
      do: {:surplus_exhausted, target},
      else: {:surplus, target}
  end

  @doc false
  def surplus_target(reading, baseline, previous) do
    case target_of(previous) do
      nil -> baseline
      target -> max(baseline, target + surplus_adjustment(battery_w(reading)))
    end
  end

  @doc false
  def surplus_adjustment(battery_power_w) do
    cond do
      battery_power_w > @surplus_deadband_w ->
        min(battery_power_w - @surplus_deadband_w, @surplus_rise_limit_w)

      battery_power_w < -@surplus_deadband_w ->
        -min(-battery_power_w - @surplus_deadband_w, @surplus_fall_limit_w)

      true ->
        0
    end
  end

  defp surplus_available?(reading),
    do: soc(reading) >= @surplus_soc_pct and charging_surplus?(reading)

  @doc false
  def charging_surplus?(reading), do: battery_w(reading) > @surplus_deadband_w

  @doc false
  def battery_discharging?(reading), do: battery_w(reading) < -@surplus_deadband_w

  @doc false
  def probe_candidate?(reading, baseline),
    do:
      soc(reading) >= @full_soc_pct and not Reading.pv_present?(reading) and
        baseline < @max_output_w

  defp protected_target(reading, load, previous) do
    if Reading.soc_at_resume?(reading),
      do: Load.effective_w(load),
      else: trimmed_target(reading, load, previous)
  end

  @doc false
  def trimmed_target(reading, load, previous) do
    ceiling = min(RubyNumeric.to_f(reading.pv_power_w), Load.effective_w(load))

    if previous && previous.trim && not is_nil(previous.target_w) do
      error = battery_w(reading) - @charge_bias_w
      clamp(previous.target_w + @trim_gain * error, 0.0, ceiling)
    else
      @entry_derate * ceiling
    end
  end

  @doc false
  def thermal_ceiling_w(reading) do
    if Reading.battery_cooled?(reading) do
      @max_output_w
    else
      span = Reading.cutoff_temp_c() - Reading.hot_temp_c()
      ratio = (Reading.cutoff_temp_c() - reading.battery_temperature_c) / span
      (@hot_output_limit_w * ratio) |> round() |> clamp(0, @hot_output_limit_w)
    end
  end

  # Ruby's Comparable#clamp, which refuses an empty range.
  defp clamp(_value, min, max) when min > max,
    do: raise(ArgumentError, "min argument must be less than or equal to max argument")

  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value

  # Ruby: `previous&.target_w` is truthy for 0.
  defp target_of(nil), do: nil
  defp target_of(%Decision{target_w: target}), do: target

  defp soc(%Reading{battery_soc_pct: soc}), do: soc
  defp battery_w(%Reading{battery_power_w: watts}), do: RubyNumeric.to_f(watts)
end
