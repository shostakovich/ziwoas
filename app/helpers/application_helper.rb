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

  # Small action glyphs drawn in the text colour (emoji render as boxes or
  # in their own colours, depending on the device). 16×16, filled.
  UI_ICONS = {
    play: "M5 3.2v9.6a.6.6 0 0 0 .9.5l7.6-4.8a.6.6 0 0 0 0-1L5.9 2.7a.6.6 0 0 0-.9.5z",
    pause: "M4 3h3v10H4zm5 0h3v10H9z",
    edit: "M11.1 1.9a1.3 1.3 0 0 1 1.8 0l1.2 1.2a1.3 1.3 0 0 1 0 1.8L6 13l-3.6.9a.4.4 0 0 1-.5-.5L2.8 9.8z",
    delete: "M6 1.5h4l.5 1H14V4H2V2.5h3.5zM3.2 5h9.6l-.7 8.6a1.5 1.5 0 0 1-1.5 1.4H5.4a1.5 1.5 0 0 1-1.5-1.4z"
  }.freeze

  def ui_icon(name)
    tag.svg(tag.path(d: UI_ICONS.fetch(name)), viewBox: "0 0 16 16", width: 16, height: 16, fill: "currentColor",
                                               aria: { hidden: true }, focusable: false, data: { icon: name })
  end

  # A number for display: decimal comma, thousands dot, true minus sign.
  def de_number(value, precision: 0) = GermanNumber.format(value, precision: precision)

  # The six tabs of the header nav (desktop) and the tab bar (mobile). A lamp's
  # page lives under /lights but is reached from the Schalten tab, so that tab
  # owns the section too.
  def main_navigation
    [
      [ root_path, "Home", "nav_dashboard_plush.webp" ],
      [ solakon_path, "PV", "nav_pv_plush.webp" ],
      [ switches_path, "Schalten", "nav_switches_plush.webp", [ "/lights" ] ],
      [ reports_path, "Berichte", "nav_reports_plush.webp" ],
      [ weather_path, "Wetter", "nav_weather_plush.webp" ],
      [ sensors_path, "Sensoren", "nav_sensors_plush.webp" ]
    ].map do |path, label, icon, sections = []|
      NavItem.new(path:, label:, icon:, current: [ path, *sections ].any? { |section| current_section?(section) })
    end
  end

  private

  # A tab stays active on its sub pages (/solakon/wirtschaftlichkeit). Home's
  # sub-page prefix would be "//", so Home is only ever active on itself.
  def current_section?(path)
    request.path == path || request.path.start_with?("#{path}/")
  end
end
