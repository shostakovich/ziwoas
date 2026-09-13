module Solakon
  class PvHour < ApplicationRecord
    self.table_name = "solakon_pv_hours"

    MIN_READINGS = 20

    validates :started_at, :pv_power_w, :reading_count, presence: true
  end
end
