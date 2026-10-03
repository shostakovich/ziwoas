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

  # Bright Sky's condition field, in German. Anything else, including no
  # condition at all, says nothing.
  CONDITION_LABELS_DE = {
    "dry" => "trocken",
    "fog" => "Nebel",
    "rain" => "Regen",
    "sleet" => "Schneeregen",
    "snow" => "Schnee",
    "hail" => "Hagel",
    "thunderstorm" => "Gewitter"
  }.freeze

  def weather_icon_label(icon)
    ICON_LABELS_DE.fetch(WeatherIcon.normalized_icon(icon), "Wetter")
  end

  def weather_condition_label(condition) = CONDITION_LABELS_DE[condition]

  # The optional rows of an hour strip. A row is there when any hour of the
  # strip has something to tell, so the cards of one strip line up without a
  # strip of night hours carrying empty sun rows.
  def weather_hour_rows(records)
    {
      wind: records.any?(&:wind_speed),
      rain: records.any? { |record| weather_hour_rain(record) },
      solar: records.any? { |record| record.daytime != "night" }
    }.select { |_row, needed| needed }.keys
  end

  # The rain line of an hour card as [text, icon alt]: the amount when it
  # rains, otherwise a likely chance of rain, otherwise nothing.
  def weather_hour_rain(record)
    if record.precipitation&.positive?
      [ "#{de_number(record.precipitation, precision: 1)} mm", "Regen" ]
    elsif record.precipitation_probability.to_i >= 30
      [ "#{record.precipitation_probability} %", "Regenwahrscheinlichkeit" ]
    end
  end
end
