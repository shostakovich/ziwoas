require "test_helper"

class WeatherControllerTest < ActionDispatch::IntegrationTest
  setup do
    WeatherRecord.delete_all
    # Tests reference 2026-05-04..06; freeze "now" so the controller's
    # Time.zone.today filter is stable regardless of the wall clock.
    travel_to Time.zone.local(2026, 5, 4, 12, 0)
  end

  teardown { travel_back }

  test "renders empty state without weather data" do
    get "/weather"

    assert_response :success
    assert_select "turbo-frame#weather_empty .empty-state", text: /Noch keine Wetterdaten/
  end

  test "hides empty state once weather data is present" do
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 12:00"), daytime: "day",
      icon: "clear-day", temperature: 20)

    get "/weather"

    assert_select "turbo-frame#weather_empty"
    assert_select "turbo-frame#weather_empty .empty-state", count: 0
  end

  test "subscribes to the weather turbo stream" do
    get "/weather"

    assert_select "turbo-cable-stream-source[channel=?]", "Turbo::StreamsChannel"
  end

  test "renders the three weather turbo frames" do
    get "/weather"

    assert_select "turbo-frame#weather_current"
    assert_select "turbo-frame#weather_today"
    assert_select "turbo-frame#weather_forecast"
  end

  test "renders current weather today and next days" do
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405, timestamp: Time.zone.parse("2026-05-04 12:00"), daytime: "day", icon: "cloudy", temperature: 16.2, condition: "dry", wind_speed: 9.7, relative_humidity: 80, cloud_cover: 100, precipitation: 0, pressure_msl: 1011.6)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405, timestamp: Time.zone.parse("2026-05-04 13:00"), daytime: "day", icon: "partly-cloudy-day", temperature: 18, precipitation: 0, solar: 0.32, wind_speed: 11)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405, timestamp: Time.zone.parse("2026-05-05 12:00"), daytime: "day", icon: "clear-day", temperature: 20, precipitation_probability: 4, solar: 0.48, wind_speed: 12)

    get "/weather"

    assert_response :success
    assert_select ".weather-current"
    assert_select ".weather-current", text: /16,2/
    assert_select ".weather-current", text: /trocken · Wind 10 km\/h · DWD/
    assert_select "h1", text: "Wetter", count: 1
    assert_select ".weather-hour-card", minimum: 1
    assert_select ".weather-day-card", minimum: 1
    assert_select ".weather-hour-card .weather-hour-solar", text: "320"
    assert_select ".weather-hour-key", text: "Wind in km/h · Sonne in W/m²"
  end

  test "hourly card renders prominent solar value during the day" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 13:00"), daytime: "day",
      icon: "partly-cloudy-day", temperature: 18, precipitation: 0,
      solar: 0.32, wind_speed: 11)

    get "/weather"

    assert_select ".weather-hour-card .weather-hour-solar", text: "320"
    assert_select ".weather-hour-card .weather-hour-solar.fw-semibold", count: 0
  end

  test "sets the sun in bold from 400 W/m² on, like a strong wind from 20 km/h" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 13:00"), daytime: "day",
      icon: "clear-day", temperature: 22, solar: 0.4, wind_speed: 19)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 14:00"), daytime: "day",
      icon: "clear-day", temperature: 22, solar: 0.399, wind_speed: 20)

    get "/weather"

    solar = css_select(".weather-hour-row .weather-hour-solar")
    wind = css_select(".weather-hour-row .weather-hour-wind")
    assert_equal [ true, false ], solar.map { |row| row["class"].split.include?("fw-semibold") }
    assert_equal [ false, true ], wind.map { |row| row["class"].split.include?("fw-semibold") }
  end

  test "names the units once per strip, only for the rows it has" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 23:00"), daytime: "night",
      icon: "clear-night", temperature: 11, wind_speed: 5)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 02:00"), daytime: "night",
      icon: "clear-night", temperature: 8)

    get "/weather"

    assert_select ".weather-hour-row .weather-hour-key", text: "Wind in km/h"
    assert_select "#seg-2026-05-05-0 .weather-hour-key", count: 0
    assert_select ".weather-hour-row .weather-hour-scroller.pb-2", count: 1
  end

  test "today row hides hours before the current hour" do
    # Clock is frozen at 2026-05-04 12:00 in setup, so 09:00 must drop out.
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 09:00"), daytime: "day",
      icon: "clear-day", temperature: 12)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 13:00"), daytime: "day",
      icon: "partly-cloudy-day", temperature: 18, solar: 0.32)

    get "/weather"

    assert_select ".weather-hour-row .weather-hour-time", text: /09:00/, count: 0
    assert_select ".weather-hour-row .weather-hour-time", text: /13:00/, count: 1
  end

  test "today row extends through end of tomorrow" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 22:00"), daytime: "night",
      icon: "clear-night", temperature: 10)

    get "/weather"

    assert_select ".weather-hour-row .weather-hour-time", text: /22:00/, count: 1
  end

  test "every hour card of a strip fills the rows the strip has, with an invisible placeholder where there is nothing to tell" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 13:00"), daytime: "day",
      icon: "partly-cloudy-day", temperature: 18, precipitation: 0, solar: 0.32, wind_speed: 11)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 14:00"), daytime: "day",
      icon: "rain-day", temperature: 17, precipitation: 0, precipitation_probability: 40, solar: 0.1)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 23:00"), daytime: "night",
      icon: "rain-night", temperature: -2, precipitation: 1.2, wind_speed: 25)

    get "/weather"

    lists = css_select(".weather-hour-card .weather-hour-extras")
    assert_equal [ 3, 3, 3 ], lists.map { |list| list.css("li").length }
    assert_equal "11", lists[0].css(".weather-hour-wind").text.squish
    assert_equal "Wind in km/h", lists[0].css(".weather-hour-wind img").sole["alt"]
    assert_equal %w[weather-hour-solar weather-hour-solar invisible],
      lists.map { |list| list.css("li")[1]["class"].split.first }
    assert_equal %w[invisible weather-hour-rain weather-hour-rain],
      lists.map { |list| list.css("li").last["class"].split.first }, "rain, the rarest row, comes last"
    assert_equal [ "" ], lists[0].css("li.invisible[aria-hidden=true]").map { |li| li.text.squish }
    assert_equal [ 1, 1, 1 ], lists.map { |list| list.css("li.invisible").length }
    assert_equal "40 %", lists[1].css(".weather-hour-rain").text.squish
    assert_equal "Regenwahrscheinlichkeit", lists[1].css(".weather-hour-rain img").sole["alt"]
    assert_equal "1,2", lists[2].css(".weather-hour-rain").text.squish
    assert_equal "Regen in mm", lists[2].css(".weather-hour-rain img").sole["alt"]
    assert_select ".weather-hour-row .weather-hour-key", text: "Wind in km/h · Sonne in W/m² · Regen in mm"
    assert_equal "25", lists[2].css(".weather-hour-wind.fw-semibold").text.squish
    assert_select ".weather-hour-card strong", text: "−2°"
  end

  test "a strip of night hours has no sun row and no rows nothing fills" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 01:00"), daytime: "night",
      icon: "clear-night", temperature: 9, wind_speed: 5)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 02:00"), daytime: "night",
      icon: "clear-night", temperature: 8)

    get "/weather"

    night_strip = css_select("#seg-2026-05-05-0 .weather-hour-extras")
    assert_equal [ 1, 1 ], night_strip.map { |list| list.css("li").length }
    assert_equal "5", night_strip[0].css(".weather-hour-wind").text.squish
    assert_equal 1, night_strip[1].css("li.invisible").length
    assert_select "#seg-2026-05-05-0 .weather-hour-solar, #seg-2026-05-05-0 .weather-hour-rain", count: 0
  end

  test "an hour card in a strip without optional rows has no extras list" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 02:00"), daytime: "night",
      icon: "clear-night", temperature: 8)

    get "/weather"

    assert_select "#seg-2026-05-05-0 .weather-hour-card", count: 1
    assert_select "#seg-2026-05-05-0 .weather-hour-extras", count: 0
  end

  test "hourly card omits the solar row entirely at night" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 23:00"), daytime: "night",
      icon: "clear-night", temperature: 11, precipitation: 0,
      solar: 0, wind_speed: 5)

    get "/weather"

    assert_select ".weather-hour-card .weather-hour-solar", count: 0
  end

  test "current weather card renders solar row with W/m² during the day" do
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 12:00"), daytime: "day",
      icon: "clear-day", temperature: 20.8, condition: "dry",
      wind_speed: 12, relative_humidity: 55, cloud_cover: 88,
      precipitation: 0, pressure_msl: 1012, solar: 0.072)

    get "/weather"

    assert_select ".weather-current-solar", text: /432 W\/m²/
  end

  test "current weather card renders Nacht in the solar row at night" do
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-04 23:00"), daytime: "night",
      icon: "clear-night", temperature: 12.0, condition: "dry",
      wind_speed: 4, relative_humidity: 70, cloud_cover: 10,
      precipitation: 0, pressure_msl: 1015, solar: 200)

    get "/weather"

    assert_select ".weather-current-solar", text: /Nacht/
    assert_select ".weather-current-solar", text: /W\/m²/, count: 0
  end

  test "day card renders weekday summary line and peak solar badge" do
    [
      { hour: 6, temp: 13, precip: 0.4, solar: 0.22 },
      { hour: 12, temp: 17, precip: 0.0, solar: 0.48 },
      { hour: 18, temp: 14, precip: 1.4, solar: 0.09 }
    ].each do |slot|
      WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
        timestamp: Time.zone.parse("2026-05-06 #{format('%02d', slot[:hour])}:00"),
        daytime: "day", icon: "partly-cloudy-day",
        temperature: slot[:temp], precipitation: slot[:precip], solar: slot[:solar])
    end

    get "/weather"

    assert_select ".weather-day-card .weather-day-summary", text: /13.*–.*17.*°C/
    assert_select ".weather-day-card .weather-day-summary", text: /Regen 1,8 mm/
    assert_select ".weather-day-card .weather-day-peak", text: /Spitze 480 W\/m²/
    assert_select ".weather-day-card .card-header > div > h3 + .weather-day-peak", 1,
                  "the peak shares the title's line, so the summary stays the second"
    assert_select ".weather-day-card .card-header > .weather-day-summary", 1
  end

  test "day card omits rain summary when total precipitation is zero" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-06 12:00"), daytime: "day",
      icon: "clear-day", temperature: 17, precipitation: 0)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-06 18:00"), daytime: "day",
      icon: "clear-day", temperature: 14, precipitation: nil)

    get "/weather"

    assert_select ".weather-day-card .weather-day-summary", text: /14.*–.*17.*°C/
    assert_select ".weather-day-card .weather-day-summary", text: /Regen/, count: 0
  end

  test "day card omits peak badge when every record has nil solar" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-06 12:00"), daytime: "day",
      icon: "cloudy", temperature: 12, precipitation: 0)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-06 18:00"), daytime: "day",
      icon: "cloudy", temperature: 11, precipitation: 0)

    get "/weather"

    assert_select ".weather-day-card .weather-day-peak", count: 0
  end

  test "day card keeps the sun row of an all-night segment empty instead of repeating Nacht" do
    (0...6).each do |h|
      WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
        timestamp: Time.zone.parse("2026-05-06 #{format('%02d', h)}:00"),
        daytime: "night", icon: "clear-night", temperature: 10 + h)
    end
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-06 12:00"), daytime: "day",
      icon: "clear-day", temperature: 17, solar: 480)

    get "/weather"

    assert_select ".weather-segment", text: /\ANacht/ do
      assert_select ".weather-segment-solar", count: 0
      assert_select "span.invisible[aria-hidden=true]", count: 1
    end
    assert_select ".weather-segment-solar", count: 1, text: /W\/m²/
  end

  test "lines the four segment tiles up row by row, an invisible stand-in where a tile has nothing to tell" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-06 09:00"), daytime: "day",
      icon: "rain-day", temperature: 14, precipitation: 0.6, solar: 0.2)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-06 15:00"), daytime: "day",
      icon: "clear-day", temperature: 19, precipitation: 0)

    get "/weather"

    tiles = css_select(".weather-day-card .weather-segment")
    assert_equal [ 5 ] * 4, tiles.map { |tile| tile.element_children.length }, "label, icon, temperature, rain and sun"
    assert_equal [ true, false, false, true ], tiles.map { |tile| tile.css(".weather-segment-temp").empty? }
    assert_equal [ "", "0,6 mm", "", "" ], tiles.map { |tile| tile.css(".weather-segment-rain").text.squish }
    assert_equal [ "", "200 W/m²", "", "" ], tiles.map { |tile| tile.css(".weather-segment-solar").text.squish }
    assert_equal 2, css_select(".weather-segment strong.invisible[aria-hidden=true]").length
    assert_equal 6, css_select(".weather-segment span.invisible[aria-hidden=true]").length
  end

  test "marks the chosen segment tile in the selection tone" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 14:00"), daytime: "day",
      icon: "clear-day", temperature: 20)

    get "/weather"

    assert_select ".weather-day-card[data-weather-segments-selected-class='active border-primary bg-primary-subtle']"
    assert_select ".weather-day-hour-row.border", count: 4
  end

  test "next-day card renders four segment tiles" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 14:00"), daytime: "day",
      icon: "clear-day", temperature: 20)

    get "/weather"

    assert_select ".weather-day-card .weather-day-segments .weather-segment", count: 4
    assert_select ".weather-day-card .weather-segment-label", text: "Nacht"
    assert_select ".weather-day-card .weather-segment-label", text: "Vormittag"
    assert_select ".weather-day-card .weather-segment-label", text: "Nachmittag"
    assert_select ".weather-day-card .weather-segment-label", text: "Abend"
  end

  test "Nachmittag segment surfaces a 14:00 thunderstorm icon" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 12:00"), daytime: "day",
      icon: "clear-day", temperature: 22)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 14:00"), daytime: "day",
      icon: "thunderstorm", temperature: 19)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 15:00"), daytime: "day",
      icon: "clear-day", temperature: 23)

    get "/weather"

    assert_select ".weather-segment", text: /Nachmittag/ do
      assert_select "img.weather-segment-icon[src*=?]", "weather_thunderstorm_day"
    end
  end

  test "segment without temperature data omits the range instead of showing 0 - 0" do
    # Vormittag (06–12) has a record with no temperature; the tile must not
    # render a fake "0 – 0°" range.
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 09:00"), daytime: "day",
      icon: "cloudy", temperature: nil)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 14:00"), daytime: "day",
      icon: "clear-day", temperature: 20)

    get "/weather"

    # Nachmittag has a temperature → range present.
    assert_select ".weather-segment", text: /Nachmittag/ do
      assert_select ".weather-segment-temp", text: /20.*–.*20°/
    end
    # Vormittag has no temperature → no .weather-segment-temp child rendered.
    assert_select ".weather-segment", text: /Vormittag/ do
      assert_select ".weather-segment-temp", count: 0
    end
  end

  test "next-day card emits hour rows hidden by default" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 14:00"), daytime: "day",
      icon: "clear-day", temperature: 20)

    get "/weather"

    assert_select ".weather-day-hours .weather-day-hour-row[hidden]", count: 4
  end

  test "assigns future weather as WeatherDay instances with aggregates" do
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 09:00"), daytime: "day",
      icon: "partly-cloudy-day", temperature: 13, precipitation: 0.4, solar: 220)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405,
      timestamp: Time.zone.parse("2026-05-05 12:00"), daytime: "day",
      icon: "clear-day", temperature: 17, precipitation: 1.4, solar: 480)

    get "/weather"

    future = controller.view_assigns["future_weather"]
    assert_equal 1, future.length
    assert_equal Date.new(2026, 5, 5), future.first.date
    assert_equal 13, future.first.temp_min
    assert_equal 17, future.first.temp_max
    assert_in_delta 1.8, future.first.precip_sum, 0.001
    assert_equal 480, future.first.solar_peak
  end

  test "GET /weather returns 200" do
    get "/weather"
    assert_response :success
  end

  test "uses outdoor sensor temperature when reading is fresh" do
    SensorReading.delete_all
    SensorReading.create!(device_id: "TEST_OUTDOOR", taken_at: 5.minutes.ago,
                          temperature: 7.7, humidity: 80, battery_pct: 100)
    WeatherRecord.delete_all
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405,
                          timestamp: Time.current, temperature: 99.9, daytime: "day")

    get "/weather"
    assert_match("7,7", @response.body)
    refute_match("99,9", @response.body)
  end

  test "falls back to brightsky temperature when sensor reading is stale" do
    SensorReading.delete_all
    SensorReading.create!(device_id: "TEST_OUTDOOR", taken_at: 2.hours.ago,
                          temperature: 7.7, humidity: 80, battery_pct: 100)
    WeatherRecord.delete_all
    WeatherRecord.create!(kind: "current", lat: 52.52, lon: 13.405,
                          timestamp: Time.current, temperature: 99.9, daytime: "day")

    get "/weather"
    assert_match("99,9", @response.body)
    refute_match("7,7",  @response.body)
  end
end
