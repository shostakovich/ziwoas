class SolakonReading < ApplicationRecord
  validates :taken_at, :active_power_w, :pv_power_w, :battery_power_w, :battery_soc_pct, presence: true
  validates :battery_soc_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :newest_first, -> { order(taken_at: :desc) }

  def self.latest_fresh(stale_after_s:, now: Time.current)
    newest_first.where("taken_at >= ?", now - stale_after_s.to_i.seconds).first
  end

  def battery_display_power_w
    -battery_power_w.to_f
  end
end
