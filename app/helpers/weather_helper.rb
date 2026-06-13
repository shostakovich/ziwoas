require "weather_icon"

module WeatherHelper
  # Human-readable German labels for the normalized weather icons,
  # used as informative alt text instead of raw enum strings.
  ICON_LABELS_DE = {
    "clear" => "klar",
    "partly-cloudy" => "teils bewölkt",
    "cloudy" => "bewölkt",
    "fog" => "Nebel",
    "wind" => "windig",
    "rain" => "Regen",
    "sleet" => "Schneeregen",
    "snow" => "Schnee",
    "hail" => "Hagel",
    "thunderstorm" => "Gewitter",
    "unknown" => "Wetter"
  }.freeze

  def weather_icon_label(icon)
    ICON_LABELS_DE.fetch(WeatherIcon.normalized_icon(icon), "Wetter")
  end
end
