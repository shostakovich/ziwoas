require "weather_icon"

module WeatherHelper
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

  CONDITION_LABELS_DE = {
    "dry" => "trocken",
    "fog" => "Nebel",
    "rain" => "Regen",
    "sleet" => "Schneeregen",
    "snow" => "Schnee",
    "hail" => "Hagel",
    "thunderstorm" => "Gewitter"
  }.freeze

  Cell = Data.define(:text, :icon, :alt, :emphasis, :classes) do
    def initialize(text:, icon: nil, alt: nil, emphasis: false, classes: nil) = super
  end

  # weather.css places the rows in this order; rain, the rarest, comes last.
  HOUR_UNITS = { wind: "Wind in km/h", solar: "Sonne in W/m²", rain: "Regen in mm" }.freeze
  HOUR_ROWS = HOUR_UNITS.keys.freeze

  # weather.css places the rows in this order.
  SEGMENT_ROWS = %i[temp rain solar].freeze

  WINDY_KM_PER_H = 20
  SUNNY_W_PER_M2 = 400

  def weather_icon_label(icon)
    ICON_LABELS_DE.fetch(WeatherIcon.normalized_icon(icon), "Wetter")
  end

  def weather_condition_label(condition) = CONDITION_LABELS_DE[condition]

  def weather_hour_rows(records)
    HOUR_ROWS.select { |row| records.any? { |record| weather_hour_cell(record, row) } }
  end

  # A chance of rain carries its own "%" and needs no key.
  def weather_hour_units(records)
    HOUR_UNITS.filter_map do |row, unit|
      unit if records.any? { |record| weather_hour_cell(record, row)&.alt == unit }
    end
  end

  def weather_hour_cell(record, row)
    case row
    when :wind
      wind = record.wind_speed
      return if wind.nil?

      windy = weather_windy?(wind)
      Cell.new(text: de_number(wind), icon: "weather_wind_day.webp", alt: HOUR_UNITS.fetch(:wind),
               emphasis: windy, classes: ("text-body" if windy))
    when :solar
      return if record.daytime == "night"

      solar = record.solar_w_per_m2
      Cell.new(text: de_number(solar), icon: "weather_clear_day.webp", alt: HOUR_UNITS.fetch(:solar),
               emphasis: weather_sunny?(solar), classes: "text-warning-emphasis")
    when :rain
      if record.precipitation&.positive?
        Cell.new(text: de_number(record.precipitation, precision: 1), icon: "weather_rain_day.webp", alt: HOUR_UNITS.fetch(:rain))
      elsif record.precipitation_probability.to_i >= 30
        Cell.new(text: de_number(record.precipitation_probability, unit: "%"), icon: "weather_rain_day.webp", alt: "Regenwahrscheinlichkeit")
      end
    end
  end

  def weather_segment_rows(segments)
    SEGMENT_ROWS.select { |row| segments.any? { |segment| weather_segment_cell(segment, row) } }
  end

  def weather_segment_cell(segment, row)
    case row
    when :temp
      return if segment.temp_min.nil?

      Cell.new(text: "#{de_number(segment.temp_min)} – #{de_number(segment.temp_max)}°", emphasis: true, classes: "fs-5")
    when :rain
      return unless segment.precip_sum.positive?

      Cell.new(text: de_number(segment.precip_sum, precision: 1, unit: "mm"), classes: "small fw-normal")
    when :solar
      solar = segment.avg_solar_w_per_m2
      return if solar.nil? || segment.all_night?

      Cell.new(text: de_number(solar, unit: "W/m²"), classes: "small text-warning-emphasis")
    end
  end

  def weather_windy?(km_per_h) = km_per_h.to_i >= WINDY_KM_PER_H

  def weather_sunny?(w_per_m2) = w_per_m2.to_i >= SUNNY_W_PER_M2
end
