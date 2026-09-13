module Solakon
  # Mean PV power over one clock hour, total and per panel, condensed from the
  # readings and snapshots by Solakon::PvHourAggregator. started_at is the
  # hour's start; an hour backed by fewer than MIN_READINGS readings has no row.
  class PvHour < ApplicationRecord
    self.table_name = "solakon_pv_hours"

    MIN_READINGS = 20

    validates :started_at, :pv_power_w, :reading_count, presence: true
  end
end
