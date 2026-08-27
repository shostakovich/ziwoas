require "solakon_client"

class SolakonSnapshot < ApplicationRecord
  PANELS = (1..4).freeze
  PANEL_FIELDS = PANELS.flat_map { |idx| [ :"pv#{idx}_power_w", :"pv#{idx}_voltage_v", :"pv#{idx}_current_a" ] }.freeze
  NUMERIC_FIELDS = (PANEL_FIELDS + %i[
    active_power_w battery_voltage_v battery_current_a battery_power_w battery_temperature_c
    battery_min_temperature_c remaining_energy_wh full_charge_capacity_ah
    design_energy_wh inverter_temperature_c grid_power_w eps_voltage_v eps_power_w
    pv_total_kwh battery_charge_total_kwh battery_discharge_total_kwh
    grid_export_total_kwh grid_import_total_kwh
  ]).freeze
  INTEGER_FIELDS = %i[battery_soc_pct battery_health_pct status1 status3 alarm1 alarm2 alarm3].freeze

  validates :taken_at, presence: true
  validates(*NUMERIC_FIELDS, numericality: true, allow_nil: true)
  validates(*INTEGER_FIELDS, numericality: { only_integer: true }, allow_nil: true)

  scope :newest_first, -> { order(taken_at: :desc) }
  scope :in_range, ->(from:, to:) { where(taken_at: from..to).order(:taken_at) }

  def self.latest = newest_first.first

  def panels
    PANELS.map do |idx|
      {
        label: "Panel #{idx}",
        power_w: public_send(:"pv#{idx}_power_w").to_f,
        voltage_v: public_send(:"pv#{idx}_voltage_v").to_f,
        current_a: public_send(:"pv#{idx}_current_a").to_f
      }
    end
  end

  def pv_power_w
    PANELS.sum { |idx| public_send(:"pv#{idx}_power_w").to_f }
  end

  def status_messages
    SolakonClient.decode_status_messages(
      status1: status1,
      status3: status3,
      alarm1: alarm1,
      alarm2: alarm2,
      alarm3: alarm3,
      bms_faults: bms_faults || []
    )
  end
end
