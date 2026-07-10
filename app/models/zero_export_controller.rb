# Pure control policy for the Solakon One. Chooses a coarse state, then a watt
# target with simple pure functions. Battery-safety thresholds live on
# SolakonReading; control tuning lives here as constants. The decision is
# written to the inverter every tick (the power register is volatile, writes
# are cheap), so `previous` is always the last applied target.
class ZeroExportController
  MAX_OUTPUT_W       = 800   # legal balcony-PV feed limit
  HOT_OUTPUT_LIMIT_W = 800   # output ceiling at HOT_TEMP_C; ramps linearly to 0 at CUTOFF_TEMP_C
  # Below resume SoC the trim aims for slight charging, not neutral, so
  # conversion losses can never bleed the SoC under 10%.
  CHARGE_BIAS_W      = 15
  TRIM_GAIN          = 0.5   # damped correction per tick; keeps noisy samples from swinging the target
  ENTRY_DERATE       = 0.85  # conservative first target on entering low-SoC protection (≈ inverter efficiency)

  Decision = Struct.new(:state, :target_w, :trim, keyword_init: true)

  # `previous` is the Decision applied on the last tick (nil on the first).
  def self.decide(reading:, load:, previous: nil)
    state = choose_state(reading: reading, previous_state: previous&.state)
    raw = target_for(state, reading: reading, load: load, previous: previous)
    target = raw.to_f.clamp(0.0, MAX_OUTPUT_W).round

    Decision.new(state: state, target_w: target,
                 trim: state == :protected && !reading.soc_at_resume?)
  end

  # Two modes only: PROTECTED (battery safety / thermal) and the normal mode,
  # which simply follows the measured household load up to the legal cap.
  def self.choose_state(reading:, previous_state:)
    protecting?(reading, previous_state) ? :protected : :normal
  end

  # Enter protection on a hard limit. Exit when BOTH SoC has resumed AND the
  # battery has cooled below HOT_TEMP_C (same threshold as entry — no hysteresis).
  def self.protecting?(reading, previous_state)
    return true if reading.soc_below_minimum? || reading.battery_hot?
    return false unless previous_state == :protected

    !(reading.soc_at_resume? && reading.battery_cooled?)
  end

  def self.target_for(state, reading:, load:, previous:)
    case state
    when :protected
      protected_target(reading, load, previous: previous)
    when :normal
      # Normal mode: target the measured load. The Solakon One serves it from PV
      # first and tops up from the battery internally; we don't manage that split.
      load.effective_w
    end
  end

  # Below resume SoC: closed-loop trim towards slight battery charging (the open
  # min(pv, load) estimate is DC-side and bleeds conversion losses out of the
  # battery). At or above resume: normal PV priority. While the battery is warm,
  # throttle the *whole* AC output to the thermal ceiling — but always follow the
  # (lower) load, since less throughput means less inverter heat.
  def self.protected_target(reading, load, previous:)
    base = if reading.soc_at_resume?
      load.effective_w
    else
      trimmed_target(reading, load, previous: previous)
    end
    [ base, thermal_ceiling_w(reading) ].min
  end

  # Damped feedback on the measured battery power (+ = charging): steer the AC
  # target so the battery charges by about CHARGE_BIAS_W instead of discharging
  # through conversion losses. min(pv, load) stays as a feedforward ceiling —
  # output beyond either would discharge or export regardless of the trim.
  # Unless the previous tick was already trimming (a bare :protected may be
  # thermal protection with a stale, high target) start conservatively below
  # the PV estimate and let the loop find the operating point.
  def self.trimmed_target(reading, load, previous:)
    ceiling = [ reading.pv_power_w.to_f, load.effective_w ].min
    return ENTRY_DERATE * ceiling unless previous&.trim && previous.target_w

    error = reading.battery_power_w.to_f - CHARGE_BIAS_W
    (previous.target_w + TRIM_GAIN * error).clamp(0.0, ceiling)
  end

  # Linear thermal de-rating, independent of SoC: at HOT_TEMP_C the ceiling is
  # the full HOT_OUTPUT_LIMIT_W, ramping straight down to 0 at CUTOFF_TEMP_C
  # (above which the battery must not discharge). A full, hot battery is throttled
  # too — the inverter simply curtails PV when there is nowhere for it to go.
  # Cooled below HOT_TEMP_C lifts the cap (same threshold, no hysteresis).
  def self.thermal_ceiling_w(reading)
    return MAX_OUTPUT_W if reading.battery_cooled?

    span  = SolakonReading::CUTOFF_TEMP_C - SolakonReading::HOT_TEMP_C
    ratio = (SolakonReading::CUTOFF_TEMP_C - reading.battery_temperature_c) / span
    (HOT_OUTPUT_LIMIT_W * ratio).round.clamp(0, HOT_OUTPUT_LIMIT_W)
  end
end
