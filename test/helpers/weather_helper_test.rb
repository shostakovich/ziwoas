require "test_helper"

class WeatherHelperTest < ActionView::TestCase
  cover "WeatherHelper#weather_condition_label"

  test "names every Bright Sky condition in German" do
    labels = %w[dry fog rain sleet snow hail thunderstorm].map { |condition| weather_condition_label(condition) }

    assert_equal %w[trocken Nebel Regen Schneeregen Schnee Hagel Gewitter], labels
  end

  test "says nothing for a missing or unknown condition" do
    assert_nil weather_condition_label(nil)
    assert_nil weather_condition_label("drizzle")
  end
end
