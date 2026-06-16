# Pure control law for zero-export: choose the inverter AC setpoint so that
# output never exceeds measured household load (which guarantees no export).
class ZeroExportController
  MAX_OUTPUT_W = 800 # legal balcony-PV feed limit
  MIN_SOC_PCT  = 10  # never discharge the battery below this

  # floor_w is an export-safe lower bound; consumption_w is the live measured
  # load. The higher of the two, clamped to [0, MAX_OUTPUT_W].
  def self.target_output_w(consumption_w:, floor_w:)
    [ consumption_w, floor_w, 0.0 ].max.clamp(0, MAX_OUTPUT_W).round
  end
end
