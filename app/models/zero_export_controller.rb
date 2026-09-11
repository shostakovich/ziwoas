# Pure control policy for the Solakon One. The public interface is one decision
# per tick; all ramping and state transitions stay inside this module.
class ZeroExportController
  MAX_OUTPUT_W       = 800
  HOT_OUTPUT_LIMIT_W = 800

  NORMAL_RISE_LIMIT_W  = 200
  SURPLUS_RISE_LIMIT_W = 200
  SURPLUS_FALL_LIMIT_W = 300
  SURPLUS_SOC_PCT      = 99
  FULL_SOC_PCT         = 100
  SURPLUS_DEADBAND_W   = 15
  PROBE_STEP_W         = 50

  # Below resume SoC the trim aims for slight charging, not neutral, so
  # conversion losses can never bleed the SoC under 10%.
  CHARGE_BIAS_W = 15
  TRIM_GAIN     = 0.5
  ENTRY_DERATE  = 0.85

  Decision = Struct.new(:state, :target_w, :trim, keyword_init: true)

  # `previous` is the Decision applied on the last tick (nil on the first).
  def self.decide(reading:, load:, previous: nil)
    state, raw = if protecting?(reading, previous&.state)
      [ :protected, protected_target(reading, load, previous: previous) ]
    else
      unprotected_decision(reading, load, previous: previous)
    end

    target = [ raw.to_f, thermal_ceiling_w(reading) ].min.clamp(0.0, MAX_OUTPUT_W).round
    Decision.new(state: state, target_w: target,
                 trim: state == :protected && !reading.soc_at_resume?)
  end

  # Enter protection on a hard limit. Exit when both SoC has resumed and the
  # battery has cooled below HOT_TEMP_C.
  def self.protecting?(reading, previous_state)
    return true if reading.soc_below_minimum? || reading.battery_hot?
    return false unless previous_state == :protected

    !(reading.soc_at_resume? && reading.battery_cooled?)
  end

  def self.unprotected_decision(reading, load, previous:)
    baseline = normal_target(load, previous: previous)

    case previous&.state
    when :surplus
      continue_surplus(reading, baseline, previous)
    when :surplus_exhausted
      continue_surplus_exit(reading, baseline, previous)
    when :probe
      resolve_probe(reading, baseline, previous)
    when :probe_blocked
      continue_probe_block(reading, baseline, previous)
    else
      start_unprotected_mode(reading, baseline, previous)
    end
  end

  # Fresh starts use the measured load immediately. Once a target has actually
  # been written, rises are limited while falls follow the load immediately.
  def self.normal_target(load, previous:)
    demand = load.effective_w.to_f
    return demand unless previous&.target_w

    [ demand, previous.target_w + NORMAL_RISE_LIMIT_W ].min
  end

  def self.start_unprotected_mode(reading, baseline, previous)
    return surplus_decision(reading, baseline, previous) if surplus_available?(reading)

    if probe_candidate?(reading, baseline)
      [ :probe, baseline + PROBE_STEP_W ]
    elsif reading.battery_soc_pct >= FULL_SOC_PCT && !reading.pv_present?
      # No headroom for a meaningful probe. Keep normal behavior, but do not
      # retry until this full-charge episode ends or charging becomes visible.
      [ :probe_blocked, baseline ]
    else
      [ :normal, baseline ]
    end
  end

  def self.continue_surplus(reading, baseline, previous)
    return [ :normal, baseline ] if reading.battery_soc_pct < SURPLUS_SOC_PCT

    surplus_decision(reading, baseline, previous)
  end

  def self.continue_surplus_exit(reading, baseline, previous)
    return [ :normal, baseline ] if reading.battery_soc_pct < SURPLUS_SOC_PCT
    return surplus_decision(reading, baseline, previous) if charging_surplus?(reading)
    return [ :probe_blocked, baseline ] if battery_discharging?(reading)

    [ :surplus_exhausted, baseline ]
  end

  def self.resolve_probe(reading, baseline, previous)
    return [ :normal, baseline ] if reading.battery_soc_pct < SURPLUS_SOC_PCT
    return [ :probe_blocked, baseline ] if battery_discharging?(reading)

    surplus_decision(reading, baseline, previous)
  end

  def self.continue_probe_block(reading, baseline, previous)
    return [ :normal, baseline ] if reading.battery_soc_pct < SURPLUS_SOC_PCT
    return surplus_decision(reading, baseline, previous) if charging_surplus?(reading)

    [ :probe_blocked, baseline ]
  end

  def self.surplus_decision(reading, baseline, previous)
    target = surplus_target(reading, baseline, previous)
    state = if battery_discharging?(reading) && target <= baseline
      :surplus_exhausted
    else
      :surplus
    end

    [ state, target ]
  end

  # At a full battery, positive battery power is solar energy that still has to
  # be redirected. Negative power means the target exceeds available PV. The
  # normal target remains the floor so measured demand keeps first priority.
  def self.surplus_target(reading, baseline, previous)
    return baseline unless previous&.target_w

    candidate = previous.target_w + surplus_adjustment(reading.battery_power_w.to_f)
    [ baseline, candidate ].max
  end

  def self.surplus_adjustment(battery_power_w)
    if battery_power_w > SURPLUS_DEADBAND_W
      [ battery_power_w - SURPLUS_DEADBAND_W, SURPLUS_RISE_LIMIT_W ].min
    elsif battery_power_w < -SURPLUS_DEADBAND_W
      -[ -battery_power_w - SURPLUS_DEADBAND_W, SURPLUS_FALL_LIMIT_W ].min
    else
      0
    end
  end

  def self.surplus_available?(reading)
    reading.battery_soc_pct >= SURPLUS_SOC_PCT && charging_surplus?(reading)
  end

  def self.charging_surplus?(reading)
    reading.battery_power_w.to_f > SURPLUS_DEADBAND_W
  end

  def self.battery_discharging?(reading)
    reading.battery_power_w.to_f < -SURPLUS_DEADBAND_W
  end

  def self.probe_candidate?(reading, baseline)
    reading.battery_soc_pct >= FULL_SOC_PCT && !reading.pv_present? && baseline < MAX_OUTPUT_W
  end

  # Below resume SoC: closed-loop trim towards slight battery charging. At or
  # above resume: follow the measured load. Thermal protection always caps the
  # complete AC output.
  def self.protected_target(reading, load, previous:)
    if reading.soc_at_resume?
      load.effective_w
    else
      trimmed_target(reading, load, previous: previous)
    end
  end

  def self.trimmed_target(reading, load, previous:)
    ceiling = [ reading.pv_power_w.to_f, load.effective_w ].min
    return ENTRY_DERATE * ceiling unless previous&.trim && previous.target_w

    error = reading.battery_power_w.to_f - CHARGE_BIAS_W
    (previous.target_w + TRIM_GAIN * error).clamp(0.0, ceiling)
  end

  # Linear thermal de-rating from full output at HOT_TEMP_C to zero at
  # CUTOFF_TEMP_C.
  def self.thermal_ceiling_w(reading)
    return MAX_OUTPUT_W if reading.battery_cooled?

    span  = SolakonReading::CUTOFF_TEMP_C - SolakonReading::HOT_TEMP_C
    ratio = (SolakonReading::CUTOFF_TEMP_C - reading.battery_temperature_c) / span
    (HOT_OUTPUT_LIMIT_W * ratio).round.clamp(0, HOT_OUTPUT_LIMIT_W)
  end
end
