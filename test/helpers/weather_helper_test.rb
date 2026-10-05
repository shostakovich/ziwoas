require "test_helper"

class WeatherHelperTest < ActionView::TestCase
  include ApplicationHelper

  cover "WeatherHelper#weather_condition_label"
  cover "WeatherHelper#weather_hour_rows"
  cover "WeatherHelper#weather_hour_cell"
  cover "WeatherHelper#weather_segment_cell"
  cover "WeatherHelper#weather_hour_units"
  cover "WeatherHelper#weather_segment_rows"
  cover "WeatherHelper#weather_windy?"
  cover "WeatherHelper#weather_sunny?"

  test "names every Bright Sky condition in German" do
    labels = %w[dry fog rain sleet snow hail thunderstorm].map { |condition| weather_condition_label(condition) }

    assert_equal %w[trocken Nebel Regen Schneeregen Schnee Hagel Gewitter], labels
  end

  test "says nothing for a missing or unknown condition" do
    assert_nil weather_condition_label(nil)
    assert_nil weather_condition_label("drizzle")
  end

  test "an hour strip has the rows any of its hours needs, the rain row last" do
    day = hour(daytime: "day")
    windy_night = hour(wind_speed: 25)
    rainy_night = hour(precipitation: 0.4)

    assert_equal %i[solar], weather_hour_rows([ hour, day ])
    assert_equal %i[wind], weather_hour_rows([ hour, windy_night ])
    assert_equal %i[rain], weather_hour_rows([ rainy_night, hour ])
    assert_equal %i[wind solar rain], weather_hour_rows([ day, windy_night, rainy_night ])
  end

  test "a strip of quiet night hours has no optional rows" do
    assert_empty weather_hour_rows([ hour, hour(wind_speed: nil, precipitation_probability: 29) ])
    assert_empty weather_hour_rows([])
  end

  test "the rain cell prefers the amount, its unit left to the key, over the chance of rain" do
    rain = ->(**attrs) { weather_hour_cell(hour(**attrs), :rain) }

    assert_equal WeatherHelper::Cell.new(text: "1,2", icon: "weather_rain_day.webp", alt: "Regen in mm"),
      rain.(precipitation: 1.2, precipitation_probability: 90)
    assert_equal WeatherHelper::Cell.new(text: "30 %", icon: "weather_rain_day.webp", alt: "Regenwahrscheinlichkeit"),
      rain.(precipitation: 0, precipitation_probability: 30)
    assert_equal "80 %", rain.(precipitation_probability: 80).text
  end

  test "the wind cell is there whenever the hour has wind, bold and in body text from 20 km/h" do
    assert_nil weather_hour_cell(hour, :wind)
    assert_equal WeatherHelper::Cell.new(text: "0", icon: "weather_wind_day.webp", alt: "Wind in km/h"),
      weather_hour_cell(hour(wind_speed: 0), :wind)
    assert_equal WeatherHelper::Cell.new(text: "20", icon: "weather_wind_day.webp", alt: "Wind in km/h", emphasis: true, classes: "text-body"),
      weather_hour_cell(hour(wind_speed: 20.4), :wind)
  end

  test "the sun cell is there in every hour of daylight, a dash where the value is missing, bold from 400 W/m²" do
    assert_nil weather_hour_cell(hour(solar: 0.5), :solar)
    assert_equal WeatherHelper::Cell.new(text: "—", icon: "weather_clear_day.webp", alt: "Sonne in W/m²", classes: "text-warning-emphasis"),
      weather_hour_cell(hour(daytime: "day"), :solar)
    assert_equal WeatherHelper::Cell.new(text: "400", icon: "weather_clear_day.webp", alt: "Sonne in W/m²", emphasis: true, classes: "text-warning-emphasis"),
      weather_hour_cell(hour(daytime: "day", solar: 0.4), :solar)
  end

  test "an hour has no cell in a row it does not know" do
    assert_nil weather_hour_cell(hour(daytime: "day", wind_speed: 30, precipitation: 3), :temp)
  end

  test "the key names the unit of every row the strip has, rain only for an amount" do
    day = hour(daytime: "day", wind_speed: 12)
    chance = hour(precipitation: 0, precipitation_probability: 60)
    rainy = hour(precipitation: 0.4)

    assert_equal [ "Wind in km/h", "Sonne in W/m²", "Regen in mm" ], weather_hour_units([ day, chance, rainy ])
    assert_equal [ "Wind in km/h", "Sonne in W/m²" ], weather_hour_units([ day, chance ]), "a chance carries its own %"
    assert_equal [ "Regen in mm" ], weather_hour_units([ rainy ])
    assert_empty weather_hour_units([ hour(precipitation: 0) ])
    assert_empty weather_hour_units([])
  end

  test "the rain cell says nothing below a 30 % chance" do
    assert_nil weather_hour_cell(hour(precipitation: 0, precipitation_probability: 29), :rain)
    assert_nil weather_hour_cell(hour, :rain)
  end

  test "a day's segment tiles share the temperature, rain and sun rows any of them needs" do
    dry_night = segment([ hour ])
    rainy_night = segment([ hour(precipitation: 0.2) ])
    sunny = segment([ hour(daytime: "day", solar: 0.3) ])
    dull_day = segment([ hour(daytime: "day") ])
    mild_night = segment([ hour(temperature: 9) ])

    assert_equal %i[rain solar], weather_segment_rows([ dry_night, rainy_night, sunny ])
    assert_equal %i[solar], weather_segment_rows([ dry_night, sunny ])
    assert_equal %i[rain], weather_segment_rows([ rainy_night, dull_day ])
    assert_equal %i[temp rain], weather_segment_rows([ rainy_night, mild_night ])
    assert_empty weather_segment_rows([ dry_night, segment([]) ])
  end

  test "an all-night segment never asks for a sun row, whatever the station measured" do
    assert_empty weather_segment_rows([ segment([ hour(solar: 0.2) ]) ])
  end

  test "a segment tile's cells: the temperature range in bold, rain in mm, the sun's average in W/m²" do
    tile = segment([ hour(daytime: "day", temperature: -2.4, precipitation: 0.25, solar: 0.3),
                     hour(daytime: "night", temperature: 11.6, solar: 0.1) ])

    assert_equal WeatherHelper::Cell.new(text: "−2 – 12°", emphasis: true, classes: "fs-5"), weather_segment_cell(tile, :temp)
    assert_equal WeatherHelper::Cell.new(text: "0,3 mm", classes: "small fw-normal"), weather_segment_cell(tile, :rain)
    assert_equal WeatherHelper::Cell.new(text: "200 W/m²", classes: "small text-warning-emphasis"), weather_segment_cell(tile, :solar)
    assert_nil weather_segment_cell(tile, :wind)
  end

  test "a segment tile has no cell where it has nothing to tell" do
    empty = segment([])
    night = segment([ hour(solar: 0.2) ])

    assert_nil weather_segment_cell(empty, :temp)
    assert_nil weather_segment_cell(empty, :rain)
    assert_nil weather_segment_cell(empty, :solar)
    assert_nil weather_segment_cell(segment([ hour(daytime: "day") ]), :solar)
    assert_nil weather_segment_cell(night, :solar)
  end

  test "wind counts as strong from 20 km/h and sun from 400 W/m²" do
    assert weather_windy?(20)
    assert weather_windy?(25)
    assert weather_sunny?(512)
    assert_not weather_windy?(19.9)
    assert_not weather_windy?(nil)
    assert weather_sunny?(400)
    assert_not weather_sunny?(399.9)
    assert_not weather_sunny?(nil)
  end

  private

  def segment(records) = WeatherSegment.new(label: "Test", hour_range: 0...6, records: records)

  def hour(daytime: "night", wind_speed: nil, precipitation: nil, precipitation_probability: nil, solar: nil, temperature: nil)
    WeatherRecord.new(kind: "forecast", daytime:, wind_speed:, precipitation:, precipitation_probability:, solar:, temperature:)
  end
end
