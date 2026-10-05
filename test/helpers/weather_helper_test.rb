require "test_helper"

class WeatherHelperTest < ActionView::TestCase
  include ApplicationHelper

  cover "WeatherHelper#weather_condition_label"
  cover "WeatherHelper#weather_hour_rows"
  cover "WeatherHelper#weather_hour_rain"
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

  test "the rain line prefers the amount over the chance of rain" do
    assert_equal [ "1,2 mm", "Regen" ], weather_hour_rain(hour(precipitation: 1.2, precipitation_probability: 90))
    assert_equal [ "30 %", "Regenwahrscheinlichkeit" ], weather_hour_rain(hour(precipitation: 0, precipitation_probability: 30))
    assert_equal [ "80 %", "Regenwahrscheinlichkeit" ], weather_hour_rain(hour(precipitation_probability: 80))
  end

  test "the rain line says nothing below a 30 % chance" do
    assert_nil weather_hour_rain(hour(precipitation: 0, precipitation_probability: 29))
    assert_nil weather_hour_rain(hour)
  end

  test "a day's segment tiles share the rain and sun rows any of them needs" do
    dry_night = segment([ hour ])
    rainy_night = segment([ hour(precipitation: 0.2) ])
    sunny = segment([ hour(daytime: "day", solar: 0.3) ])
    dull_day = segment([ hour(daytime: "day") ])

    assert_equal %i[rain solar], weather_segment_rows([ dry_night, rainy_night, sunny ])
    assert_equal %i[solar], weather_segment_rows([ dry_night, sunny ])
    assert_equal %i[rain], weather_segment_rows([ rainy_night, dull_day ])
    assert_empty weather_segment_rows([ dry_night, segment([]) ])
  end

  test "an all-night segment never asks for a sun row, whatever the station measured" do
    assert_empty weather_segment_rows([ segment([ hour(solar: 0.2) ]) ])
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

  def hour(daytime: "night", wind_speed: nil, precipitation: nil, precipitation_probability: nil, solar: nil)
    WeatherRecord.new(kind: "forecast", daytime:, wind_speed:, precipitation:, precipitation_probability:, solar:)
  end
end
