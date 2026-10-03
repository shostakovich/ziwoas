module ApplicationHelper
  # Every battery face the inverter can wear, keyed by Solakon::Reading#battery_state.
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

  NavItem = Data.define(:path, :label, :icon, :current)

  # The six tabs of the header nav (desktop) and the tab bar (mobile).
  def main_navigation
    [
      [ root_path, "Home", "nav_dashboard_plush.webp" ],
      [ solakon_path, "PV", "nav_pv_plush.webp" ],
      [ switches_path, "Schalten", "nav_switches_plush.webp" ],
      [ reports_path, "Berichte", "nav_reports_plush.webp" ],
      [ weather_path, "Wetter", "nav_weather_plush.webp" ],
      [ sensors_path, "Sensoren", "nav_sensors_plush.webp" ]
    ].map { |path, label, icon| NavItem.new(path:, label:, icon:, current: current_section?(path)) }
  end

  private

  # A tab stays active on its sub pages (/solakon/wirtschaftlichkeit). Home's
  # sub-page prefix would be "//", so Home is only ever active on itself.
  def current_section?(path)
    request.path == path || request.path.start_with?("#{path}/")
  end
end
