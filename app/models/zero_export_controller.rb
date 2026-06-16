# Pure control law for zero-export: choose the inverter AC setpoint so that
# output never exceeds measured household load (which guarantees no export).
class ZeroExportController
  MAX_OUTPUT_W = 800 # legal balcony-PV feed limit
  MIN_SOC_PCT  = 10  # never discharge the battery below this

  # consumption_w is the live measured load, or nil when no fresh sample is
  # available. With fresh data we follow it directly (the sum of measured
  # consumers is <= true load, so this never exports). Only when consumption is
  # unknown (nil) do we fall back to the export-safe floor. The floor is NOT a
  # lower bound over fresh data — using it that way could command more than the
  # real load and feed into the grid.
  def self.target_output_w(consumption_w:, floor_w:)
    basis = consumption_w.nil? ? floor_w : consumption_w
    basis.clamp(0, MAX_OUTPUT_W).round
  end
end
