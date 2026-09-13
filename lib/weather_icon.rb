require "time"

module WeatherIcon
  ICONS = %w[
    clear partly-cloudy cloudy fog wind rain sleet snow hail thunderstorm unknown
  ].freeze

  def self.asset_name(icon, daytime)
    base = normalized_icon(icon)
    suffix = normalized_daytime(daytime)
    "weather_#{base.tr("-", "_")}_#{suffix}.webp"
  end

  # The icon says it outright, or the sun over the house decides.
  def self.daytime_for(icon:, timestamp:, location:)
    return "day" if icon.to_s.end_with?("-day")
    return "night" if icon.to_s.end_with?("-night")

    location.sun.daytime?(timestamp) ? "day" : "night"
  end

  def self.normalized_icon(icon)
    raw = icon.to_s
    raw = raw.delete_suffix("-day").delete_suffix("-night")
    ICONS.include?(raw) ? raw : "unknown"
  end

  def self.normalized_daytime(daytime)
    daytime.to_s == "night" ? "night" : "day"
  end
end
