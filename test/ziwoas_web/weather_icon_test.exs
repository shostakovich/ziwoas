defmodule ZiwoasWeb.WeatherIconTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Weather.{Record, Segment}
  alias ZiwoasWeb.WeatherIcon

  defp record(attrs), do: struct!(%Record{kind: :forecast, daytime: "day"}, attrs)

  test "maps Bright Sky day, night and neutral icons" do
    assert WeatherIcon.asset_name("clear-day", "day") == "weather_clear_day.webp"
    assert WeatherIcon.asset_name("clear-night", "night") == "weather_clear_night.webp"
    assert WeatherIcon.asset_name("partly-cloudy-day", "day") == "weather_partly_cloudy_day.webp"

    assert WeatherIcon.asset_name("partly-cloudy-night", "night") ==
             "weather_partly_cloudy_night.webp"

    assert WeatherIcon.asset_name("rain", "day") == "weather_rain_day.webp"
    assert WeatherIcon.asset_name("rain", "night") == "weather_rain_night.webp"
  end

  test "falls back for unknown icons and normalises the daytime" do
    assert WeatherIcon.asset_name("not-real", "day") == "weather_unknown_day.webp"
    assert WeatherIcon.asset_name(nil, "night") == "weather_unknown_night.webp"
    assert WeatherIcon.asset_name("rain", "morning") == "weather_rain_day.webp"
  end

  test "a record's and a segment's plush" do
    assert WeatherIcon.plush_name(record(icon: "partly-cloudy-night", daytime: "night")) ==
             "weather-partly-cloudy-night"

    assert WeatherIcon.plush_name("not-real", "morning") == "weather-unknown-day"

    segment = %Segment{
      label: :afternoon,
      hours: 12..17//1,
      records: [record(icon: "clear-day"), record(icon: "thunderstorm")]
    }

    assert WeatherIcon.plush_name(segment) == "weather-thunderstorm-day"
    assert WeatherIcon.plush_name(segment) in ZiwoasWeb.Plush.names()

    foggy_dawn = [record(icon: "fog", daytime: "night"), record(icon: "fog", daytime: "night")]
    morning = %Segment{segment | records: foggy_dawn ++ List.duplicate(record(icon: "cloudy"), 4)}
    assert WeatherIcon.plush_name(morning) == "weather-fog-day"

    sunset = [
      record(icon: "partly-cloudy-day")
      | List.duplicate(record(icon: "partly-cloudy-night", daytime: "night"), 5)
    ]

    assert WeatherIcon.plush_name(%Segment{segment | records: sunset}) ==
             "weather-partly-cloudy-night"
  end

  test "the current weather's plush is night by the record or once the sun is down" do
    assert WeatherIcon.current_plush_name(record(icon: "cloudy"), true) == "weather-cloudy-day"
    assert WeatherIcon.current_plush_name(record(icon: "cloudy"), false) == "weather-cloudy-night"

    assert WeatherIcon.current_plush_name(record(icon: "cloudy", daytime: "night"), true) ==
             "weather-cloudy-night"
  end

  test "German names, Wetter for anything unknown" do
    assert WeatherIcon.label("partly-cloudy-night") == "teils bewölkt"
    assert WeatherIcon.label("bogus") == "Wetter"
    assert WeatherIcon.label(nil) == "Wetter"
  end
end
