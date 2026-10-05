require_relative "application_system_test_case"

class WeatherRowsAlignmentTest < ApplicationSystemTestCase
  HOUR_ROWS = %w[time icon temp wind solar rain].freeze
  TILE_ROWS = %w[label icon temp rain solar].freeze

  setup do
    WeatherRecord.delete_all
    travel_to Time.zone.local(2026, 5, 4, 17, 30)

    forecast("2026-05-04 18:00", "day", temperature: 18, solar: 0.45, wind_speed: 22)
    forecast("2026-05-04 19:00", "day", temperature: 17, solar: 0.1, precipitation_probability: 50)
    forecast("2026-05-04 21:00", "night", temperature: 14, wind_speed: 5, precipitation: 1.2)
    forecast("2026-05-04 22:00", "night", temperature: 13)
    forecast("2026-05-05 03:00", "night", temperature: 8, precipitation: 0.6)
    forecast("2026-05-05 09:00", "day", temperature: 12, solar: 0.3)
    forecast("2026-05-05 14:00", "day", temperature: 16)
    forecast("2026-05-05 19:00", "day", solar: 0.3, wind_speed: 10)
    forecast("2026-05-05 20:00", "day", solar: 0.1)
    forecast("2026-05-05 22:00", "night", wind_speed: 4)
  end

  teardown do
    travel_back
    page.current_window.resize_to(1400, 1400)
  end

  test "on a phone every row of today's strip sits at one height across its hours, wherever an hour lacks it" do
    page.current_window.resize_to(375, 812)
    visit "/weather"
    assert_selector ".weather-hour-row .weather-hour-card", count: 10

    cards = hour_rows(".weather-hour-row")
    %w[wind solar rain].each do |row|
      assert cards.any? { |card| card[row].nil? }, "some hour has no #{row}, or the test proves nothing"
    end
    assert_aligned cards, HOUR_ROWS
  end

  test "the hours of a day segment line up, the night hour without sun beside the day hour without wind" do
    visit "/weather"
    first(".weather-day-card").find("button.weather-segment[data-segment-index='3']").click
    assert_selector "#seg-2026-05-05-3", visible: :visible

    cards = hour_rows("#seg-2026-05-05-3")
    assert_equal [ %w[wind solar], %w[solar], %w[wind] ], cards.map { |card| %w[wind solar].select { |row| card[row] } }
    assert_aligned cards, HOUR_ROWS
  end

  test "the segment tiles of a line share their rows, on a desktop and on a phone" do
    [ [ 1280, 900, 1 ], [ 375, 812, 2 ] ].each do |width, height, lines|
      page.current_window.resize_to(width, height)
      visit "/weather"
      tiles = tile_rows
      assert_equal 4, tiles.length

      by_line = tiles.group_by { |tile| tile["tile"].round }.values
      assert_equal lines, by_line.length, "#{width} px: tiles per line"
      by_line.each { |line| assert_aligned line, TILE_ROWS }
      %w[temp rain solar].each do |row|
        assert tiles.any? { |tile| tile[row].nil? }, "some tile has no #{row}, or the test proves nothing"
      end
    end
  end

  private

  def forecast(timestamp, daytime, **attrs)
    WeatherRecord.create!(kind: "forecast", lat: 52.52, lon: 13.405, timestamp: Time.zone.parse(timestamp),
                          daytime:, icon: daytime == "night" ? "clear-night" : "partly-cloudy-day", **attrs)
  end

  def hour_rows(strip)
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll("#{strip} .weather-hour-card")].map((card) => {
        const top = (selector) => card.querySelector(selector)?.getBoundingClientRect().top ?? null
        return {
          time: top(".weather-hour-time"), icon: top("img.weather-icon"), temp: top("strong"),
          wind: top(".weather-hour-wind"), solar: top(".weather-hour-solar"), rain: top(".weather-hour-rain")
        }
      })
    JS
  end

  def tile_rows
    page.evaluate_script(<<~JS)
      [...document.querySelector(".weather-day-segments").querySelectorAll(".weather-segment")].map((tile) => {
        const top = (selector) => tile.querySelector(selector)?.getBoundingClientRect().top ?? null
        return {
          tile: tile.getBoundingClientRect().top, label: top(".weather-segment-label"), icon: top(".weather-segment-icon"),
          temp: top(".weather-segment-temp"), rain: top(".weather-segment-rain"), solar: top(".weather-segment-solar")
        }
      })
    JS
  end

  def assert_aligned(items, rows)
    rows.each do |row|
      tops = items.filter_map { |item| item[row] }
      next if tops.length < 2

      assert_operator tops.max - tops.min, :<=, 1, "#{row} sits at #{tops.uniq.inspect}"
    end
  end
end
