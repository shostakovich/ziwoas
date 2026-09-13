require "test_helper"

class WeatherReportLoaderTest < ActiveSupport::TestCase
  cover "WeatherReportLoader*"

  setup do
    WeatherRecord.delete_all
    @loader = WeatherReportLoader.new(location: location)
  end

  test "daily aggregates solar and resolves dominant icon per local day" do
    create_historic(Time.utc(2026, 5, 1, 6),  solar: 0.10, icon: "clear-day",         daytime: "day")
    create_historic(Time.utc(2026, 5, 1, 12), solar: 0.50, icon: "partly-cloudy-day", daytime: "day")
    create_historic(Time.utc(2026, 5, 1, 18), solar: 0.05, icon: "rain",              daytime: "day")
    create_historic(Time.utc(2026, 5, 1, 22), solar: 0.00, icon: "clear-night",       daytime: "night")

    daily = @loader.daily(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_equal [ "2026-05-01" ], daily.keys
    assert_in_delta 0.65, daily["2026-05-01"][:solar_kwh_per_m2], 0.001
    # rain dominates day-only severity vs clear / partly-cloudy
    assert_equal "weather_rain_day.webp", daily["2026-05-01"][:asset_name]
    assert_equal "rain", daily["2026-05-01"][:alt]
  end

  test "daily skips days without records" do
    create_historic(Time.utc(2026, 5, 1, 12), solar: 0.4, icon: "clear-day", daytime: "day")

    daily = @loader.daily(Date.new(2026, 4, 30), Date.new(2026, 5, 2))

    assert_equal [ "2026-05-01" ], daily.keys
  end

  test "hourly returns one entry per historic record in range" do
    create_historic(Time.utc(2026, 5, 1, 10), solar: 0.40, icon: "clear-day", daytime: "day")
    create_historic(Time.utc(2026, 5, 1, 11), solar: 0.55, icon: "clear-day", daytime: "day")

    hourly = @loader.hourly(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_equal 2, hourly.size
    assert_equal Time.utc(2026, 5, 1, 10).to_i, hourly.first[:ts]
    assert_in_delta 400.0, hourly.first[:solar_w_per_m2]
    assert_equal "weather_clear_day.webp", hourly.first[:asset_name]
  end

  test "a location without coordinates has no weather to report" do
    create_historic(Time.utc(2026, 5, 1, 12), solar: 0.4, icon: "clear-day", daytime: "day")
    loader = WeatherReportLoader.new(location: Location.new(timezone: "Europe/Berlin"))

    assert_empty loader.daily(Date.new(2026, 5, 1), Date.new(2026, 5, 1))
    assert_empty loader.hourly(Date.new(2026, 5, 1), Date.new(2026, 5, 1))
  end

  # `hourly` has no per-record date re-check (unlike `daily`), so it is the
  # one place that isolates the SQL range boundary computed by
  # `local_midnight` from the per-record `local_date` grouping. The suite's
  # Time.zone (Europe/Berlin, config/ziwoas.test.yml) must never substitute
  # for the zone actually configured on the loader.
  test "reads the day off the location's own clock, not the suite's" do
    loader = WeatherReportLoader.new(location: location(timezone: "UTC"))
    # 23:00 UTC on April 30th is before UTC midnight May 1st, but would
    # already be inside the requested day if the zone silently fell back
    # to the suite's Europe/Berlin default (starts 22:00 UTC April 30th).
    create_historic(Time.utc(2026, 4, 30, 23), solar: 0.2, icon: "clear-day", daytime: "day")

    hourly = loader.hourly(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_empty hourly
  end

  test "daily groups by the configured timezone, not the global default" do
    loader = WeatherReportLoader.new(location: location(timezone: "America/New_York"))
    # 02:00 UTC on May 1st is still April 30th in America/New_York (-4 in summer)
    # but already May 1st in the suite's Europe/Berlin default.
    create_historic(Time.utc(2026, 5, 1, 2), solar: 0.2, icon: "clear-day", daytime: "day")

    daily = loader.daily(Date.new(2026, 4, 30), Date.new(2026, 5, 1))

    assert_equal [ "2026-04-30" ], daily.keys
  end

  test "historic range boundaries use the configured timezone, not the global default" do
    loader = WeatherReportLoader.new(location: location(timezone: "America/New_York"))
    # America/New_York midnight on May 1st is 04:00 UTC. A record one hour
    # before that falls outside the requested day in that zone, but would
    # fall inside it under the suite's Europe/Berlin default (starts 22:00
    # UTC April 30th).
    create_historic(Time.utc(2026, 5, 1, 3), solar: 0.2, icon: "clear-day", daytime: "day")

    hourly = loader.hourly(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_empty hourly
  end

  test "day_segment picks the dominant icon only from daytime records when some exist" do
    create_historic(Time.utc(2026, 5, 1, 12), solar: 0.3, icon: "clear-day", daytime: "day")
    # More severe than "clear", but at night: must not out-rank the day icon.
    create_historic(Time.utc(2026, 5, 1, 19), solar: 0.0, icon: "thunderstorm", daytime: "night")

    daily = @loader.daily(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_equal "clear", daily["2026-05-01"][:alt]
    assert_equal "weather_clear_day.webp", daily["2026-05-01"][:asset_name]
  end

  test "day_segment falls back to all records when none are marked daytime" do
    create_historic(Time.utc(2026, 5, 1, 19), solar: 0.0, icon: "clear-night", daytime: "night")

    daily = @loader.daily(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_equal "clear", daily["2026-05-01"][:alt]
  end

  test "excludes a record exactly at the local midnight after the end date" do
    loader = WeatherReportLoader.new(location: location(timezone: "UTC"))
    create_historic(Time.utc(2026, 5, 2, 0), solar: 0.1, icon: "clear-day", daytime: "day")
    create_historic(Time.utc(2026, 5, 1, 23), solar: 0.2, icon: "clear-day", daytime: "day")

    hourly = loader.hourly(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_equal 1, hourly.size
    assert_equal Time.utc(2026, 5, 1, 23).to_i, hourly.first[:ts]
  end

  test "orders hourly records chronologically regardless of insertion order" do
    create_historic(Time.utc(2026, 5, 1, 18), solar: 0.05, icon: "clear-day", daytime: "day")
    create_historic(Time.utc(2026, 5, 1, 6),  solar: 0.10, icon: "clear-day", daytime: "day")

    hourly = @loader.hourly(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_equal [ Time.utc(2026, 5, 1, 6).to_i, Time.utc(2026, 5, 1, 18).to_i ], hourly.map { |h| h[:ts] }
  end

  test "counts only historic records, not forecast or current ones in the same range" do
    create_historic(Time.utc(2026, 5, 1, 10), solar: 0.2, icon: "clear-day", daytime: "day")
    WeatherRecord.create!(kind: "forecast", timestamp: Time.utc(2026, 5, 1, 11),
                           lat: 48.15, lon: 11.26, solar: 0.3, icon: "clear-day", daytime: "day")

    hourly = @loader.hourly(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_equal 1, hourly.size
  end

  test "day_solar_kwh returns nil rather than zero when every record's solar reading is missing" do
    create_historic(Time.utc(2026, 5, 1, 10), solar: nil, icon: "clear-day", daytime: "day")

    daily = @loader.daily(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_nil daily["2026-05-01"][:solar_kwh_per_m2]
  end

  test "rounds the daily solar total to three decimals" do
    create_historic(Time.utc(2026, 5, 1, 10), solar: 0.12345, icon: "clear-day", daytime: "day")

    daily = @loader.daily(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_equal 0.123, daily["2026-05-01"][:solar_kwh_per_m2]
  end

  test "includes the raw icon string in the hourly alt field" do
    create_historic(Time.utc(2026, 5, 1, 10), solar: 0.3, icon: "clear-day", daytime: "day")

    hourly = @loader.hourly(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_equal "clear-day", hourly.first[:alt]
  end

  test "stringifies a missing icon in the hourly alt field rather than leaving it nil" do
    create_historic(Time.utc(2026, 5, 1, 10), solar: 0.3, icon: nil, daytime: "day")

    hourly = @loader.hourly(Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_equal "", hourly.first[:alt]
  end

  test "day_segment labels itself 'day' and spans the full 24 hours, whatever it pools" do
    create_historic(Time.utc(2026, 5, 1, 12), solar: 0.3, icon: "clear-day", daytime: "day")

    segment = @loader.send(:day_segment, WeatherRecord.historic.to_a)

    assert_equal "day", segment.label
    assert_equal(0..23, segment.hour_range)
  end

  test "historic_records_in_range materializes an Array, not a lazy relation" do
    create_historic(Time.utc(2026, 5, 1, 12), solar: 0.3, icon: "clear-day", daytime: "day")

    records = @loader.send(:historic_records_in_range, Date.new(2026, 5, 1), Date.new(2026, 5, 1))

    assert_kind_of Array, records
  end

  private

  def location(timezone: "Europe/Berlin") = Location.new(timezone: timezone, lat: 48.15, lon: 11.26)

  def create_historic(ts, solar:, icon:, daytime:)
    WeatherRecord.create!(
      kind: "historic",
      timestamp: ts,
      lat: 48.15,
      lon: 11.26,
      solar: solar,
      icon: icon,
      daytime: daytime
    )
  end
end
