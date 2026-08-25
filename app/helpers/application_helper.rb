module ApplicationHelper
  # Every battery face the inverter can wear, keyed by SolakonReading#battery_state.
  # A discharging battery and an unknown state both show the normal face.
  BATTERY_ASSETS = {
    "normal"      => "solakon_battery_normal.webp",
    "discharging" => "solakon_battery_normal.webp",
    "charging"    => "solakon_battery_charging.webp",
    "low"         => "solakon_battery_low.webp",
    "hot"         => "solakon_battery_hot.webp",
    "cold"        => "solakon_battery_cold.webp",
    "fault"       => "solakon_battery_fault.webp"
  }.freeze

  DEFAULT_BATTERY_ASSET = BATTERY_ASSETS.fetch("normal")
end
