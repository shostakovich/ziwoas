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

  test "a record's and a segment's image" do
    assert WeatherIcon.asset_name(record(icon: "partly-cloudy-night", daytime: "night")) ==
             "weather_partly_cloudy_night.webp"

    segment = %Segment{
      label: :afternoon,
      hours: 12..17//1,
      records: [record(icon: "clear-day"), record(icon: "thunderstorm")]
    }

    assert WeatherIcon.asset_name(segment) == "weather_thunderstorm_day.webp"
  end

  test "German names, Wetter for anything unknown" do
    assert WeatherIcon.label("partly-cloudy-night") == "teils bewölkt"
    assert WeatherIcon.label("bogus") == "Wetter"
    assert WeatherIcon.label(nil) == "Wetter"
  end

  test "the dashboard hero: the sun until the first sync, then the current icon" do
    assert WeatherIcon.dashboard(nil) == {"icon_sonne.webp", "Sonne"}

    assert WeatherIcon.dashboard(record(icon: "rain", daytime: "night")) ==
             {"weather_rain_night.webp", "rain"}

    assert WeatherIcon.dashboard(record(icon: "  ")) == {"weather_unknown_day.webp", "Sonne"}
    assert WeatherIcon.dashboard(record(icon: nil)) == {"weather_unknown_day.webp", "Sonne"}
  end
end
