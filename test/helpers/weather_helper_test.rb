require "test_helper"

class WeatherHelperTest < ActionView::TestCase
  include ApplicationHelper

  cover "WeatherHelper#weather_condition_label"
  cover "WeatherHelper#weather_hour_rows"
  cover "WeatherHelper#weather_hour_rain"

  test "names every Bright Sky condition in German" do
    labels = %w[dry fog rain sleet snow hail thunderstorm].map { |condition| weather_condition_label(condition) }

    assert_equal %w[trocken Nebel Regen Schneeregen Schnee Hagel Gewitter], labels
  end

  test "says nothing for a missing or unknown condition" do
    assert_nil weather_condition_label(nil)
    assert_nil weather_condition_label("drizzle")
  end

  test "an hour strip has the rows any of its hours needs, the sun row last" do
    day = hour(daytime: "day")
    windy_night = hour(wind_speed: 25)
    rainy_night = hour(precipitation: 0.4)

    assert_equal %i[solar], weather_hour_rows([ hour, day ])
    assert_equal %i[wind], weather_hour_rows([ hour, windy_night ])
    assert_equal %i[rain], weather_hour_rows([ rainy_night, hour ])
    assert_equal %i[wind rain solar], weather_hour_rows([ day, windy_night, rainy_night ])
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

  private

  def hour(daytime: "night", wind_speed: nil, precipitation: nil, precipitation_probability: nil)
    WeatherRecord.new(daytime:, wind_speed:, precipitation:, precipitation_probability:)
  end
end
