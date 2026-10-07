defmodule ZiwoasWeb.WeatherComponentsTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Weather.{Record, Segment}
  alias ZiwoasWeb.WeatherComponents, as: W
  alias ZiwoasWeb.WeatherComponents.Cell

  defp hour(attrs \\ []), do: struct!(%Record{kind: "forecast", daytime: "night"}, attrs)
  defp segment(records), do: %Segment{label: "Test", hours: 0..5//1, records: records}

  test "names every Bright Sky condition in German, nothing for others" do
    assert Enum.map(~w[dry fog rain sleet snow hail thunderstorm], &W.condition_label/1) ==
             ~w[trocken Nebel Regen Schneeregen Schnee Hagel Gewitter]

    assert W.condition_label(nil) == nil
    assert W.condition_label("drizzle") == nil
  end

  test "icon labels fall back to Wetter" do
    assert W.icon_label("partly-cloudy-night") == "teils bewölkt"
    assert W.icon_label("bogus") == "Wetter"
  end

  test "an hour strip has the rows any of its hours needs, the rain row last" do
    day = hour(daytime: "day")
    windy_night = hour(wind_speed: 25.0)
    rainy_night = hour(precipitation: 0.4)

    assert W.hour_rows([hour(), day]) == [:solar]
    assert W.hour_rows([hour(), windy_night]) == [:wind]
    assert W.hour_rows([rainy_night, hour()]) == [:rain]
    assert W.hour_rows([day, windy_night, rainy_night]) == [:wind, :solar, :rain]
    assert W.hour_rows([hour(), hour(precipitation_probability: 29)]) == []
    assert W.hour_rows([]) == []
  end

  test "the rain cell prefers the amount over the chance of rain, from 30 %" do
    assert W.hour_cell(hour(precipitation: 1.2, precipitation_probability: 90), :rain) ==
             %Cell{text: "1,2", icon: "weather_rain_day.webp", alt: "Regen in mm"}

    assert W.hour_cell(hour(precipitation: 0.0, precipitation_probability: 30), :rain) ==
             %Cell{text: "30 %", icon: "weather_rain_day.webp", alt: "Regenwahrscheinlichkeit"}

    assert W.hour_cell(hour(precipitation_probability: 80), :rain).text == "80 %"
    assert W.hour_cell(hour(precipitation: 0.0, precipitation_probability: 29), :rain) == nil
    assert W.hour_cell(hour(), :rain) == nil
  end

  test "the wind cell exists whenever there is wind, bold from 20 km/h" do
    assert W.hour_cell(hour(), :wind) == nil

    assert W.hour_cell(hour(wind_speed: 0.0), :wind) ==
             %Cell{text: "0", icon: "weather_wind_day.webp", alt: "Wind in km/h"}

    assert W.hour_cell(hour(wind_speed: 20.4), :wind) ==
             %Cell{
               text: "20",
               icon: "weather_wind_day.webp",
               alt: "Wind in km/h",
               emphasis: true,
               classes: "text-body"
             }
  end

  test "the sun cell exists in daylight, a dash without value, bold from 400 W/m²" do
    assert W.hour_cell(hour(solar: 0.5), :solar) == nil

    assert W.hour_cell(hour(daytime: "day"), :solar) ==
             %Cell{
               text: "—",
               icon: "weather_clear_day.webp",
               alt: "Sonne in W/m²",
               classes: "text-warning-emphasis"
             }

    assert %Cell{text: "400", emphasis: true} =
             W.hour_cell(hour(daytime: "day", solar: 0.4), :solar)

    assert W.hour_cell(hour(daytime: "day", wind_speed: 30.0, precipitation: 3.0), :temp) == nil
  end

  test "the key names the unit of every row the strip has, rain only for an amount" do
    day = hour(daytime: "day", wind_speed: 12.0)
    chance = hour(precipitation: 0.0, precipitation_probability: 60)
    rainy = hour(precipitation: 0.4)

    assert W.hour_units([day, chance, rainy]) == ["Wind in km/h", "Sonne in W/m²", "Regen in mm"]
    assert W.hour_units([day, chance]) == ["Wind in km/h", "Sonne in W/m²"]
    assert W.hour_units([rainy]) == ["Regen in mm"]
    assert W.hour_units([hour(precipitation: 0.0)]) == []
    assert W.hour_units([]) == []
  end

  test "segment tiles share the temperature, rain and sun rows any of them needs" do
    dry_night = segment([hour()])
    rainy_night = segment([hour(precipitation: 0.2)])
    sunny = segment([hour(daytime: "day", solar: 0.3)])
    dull_day = segment([hour(daytime: "day")])
    mild_night = segment([hour(temperature: 9.0)])

    assert W.segment_rows([dry_night, rainy_night, sunny]) == [:rain, :solar]
    assert W.segment_rows([dry_night, sunny]) == [:solar]
    assert W.segment_rows([rainy_night, dull_day]) == [:rain]
    assert W.segment_rows([rainy_night, mild_night]) == [:temp, :rain]
    assert W.segment_rows([dry_night, segment([])]) == []
    assert W.segment_rows([segment([hour(solar: 0.2)])]) == []
  end

  test "a segment tile's cells, and none where it has nothing to tell" do
    tile =
      segment([
        hour(daytime: "day", temperature: -2.4, precipitation: 0.25, solar: 0.3),
        hour(daytime: "night", temperature: 11.6, solar: 0.1)
      ])

    assert W.segment_cell(tile, :temp) == %Cell{text: "−2 – 12°", emphasis: true, classes: "fs-5"}
    assert W.segment_cell(tile, :rain) == %Cell{text: "0,3 mm", classes: "small fw-normal"}

    assert W.segment_cell(tile, :solar) ==
             %Cell{text: "200 W/m²", classes: "small text-warning-emphasis"}

    assert W.segment_cell(tile, :wind) == nil

    for row <- [:temp, :rain, :solar], do: assert(W.segment_cell(segment([]), row) == nil)
    assert W.segment_cell(segment([hour(daytime: "day")]), :solar) == nil
    assert W.segment_cell(segment([hour(solar: 0.2)]), :solar) == nil
  end

  test "strong wind from 20 km/h, strong sun from 400 W/m²" do
    assert W.windy?(20) and W.windy?(25)
    refute W.windy?(19.9) or W.windy?(nil)
    assert W.sunny?(400) and W.sunny?(512)
    refute W.sunny?(399.9) or W.sunny?(nil)
  end
end
