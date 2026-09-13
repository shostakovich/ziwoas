require "test_helper"

class Shading::BuilderTest < ActiveSupport::TestCase
  cover "Shading::Builder*"

  LAT = 52.52
  LON = 13.405
  JULY = Date.new(2026, 7, 1)

  setup do
    Solakon::PvHour.delete_all
    WeatherRecord.delete_all
  end

  def pv_hour(local_hour, watts, date: JULY, panels: [ 100.0, 100.0, 100.0, 100.0 ])
    Solakon::PvHour.create!(
      started_at: Time.zone.local(date.year, date.month, date.day, local_hour),
      pv_power_w: watts, reading_count: 120,
      pv1_power_w: panels[0], pv2_power_w: panels[1], pv3_power_w: panels[2], pv4_power_w: panels[3]
    )
  end

  def weather(local_hour, solar:, date: JULY, lat: LAT, lon: LON)
    WeatherRecord.create!(
      kind: "historic", daytime: "day", lat: lat, lon: lon,
      timestamp: Time.zone.local(date.year, date.month, date.day, local_hour), solar: solar
    )
  end

  def build(lat: LAT, lon: LON)
    builder(lat: lat, lon: lon).build
  end

  def builder(lat: LAT, lon: LON, timezone: "Europe/Berlin")
    Shading::Builder.new(location: Location.new(timezone: timezone, lat: lat, lon: lon))
  end

  test "reads the day's shape from the PV hours alone" do
    pv_hour(12, 640.0)

    profile = build.profiles.sole

    assert_equal 7, profile.month
    assert_equal [ [ 12, 640.0 ] ], profile.curve(:measured).points
  end

  test "joins the station's irradiance of the same hour onto the PV hour" do
    pv_hour(12, 400.0)
    weather(12, solar: 0.5)

    profile = build.profiles.sole

    assert_equal [ [ 12, 400.0 ] ], profile.curve(:expected).points
  end

  test "ignores the irradiance measured somewhere else" do
    pv_hour(12, 400.0)
    weather(12, solar: 0.5, lat: 48.15, lon: 11.26)

    assert_empty build.profiles.sole.curve(:expected).points
  end

  test "calibrates on the best hour and shrugs off a single outlier" do
    20.times { |index| pv_hour(12, 400.0, date: Date.new(2026, 7, 1 + index)) }
    20.times { |index| weather(12, solar: 0.5, date: Date.new(2026, 7, 1 + index)) }
    pv_hour(12, 2000.0, date: Date.new(2026, 8, 1))
    weather(12, solar: 0.5, date: Date.new(2026, 8, 1))

    august = build.profiles.find { |profile| profile.month == 8 }

    # 0.8 W per W/m², the ratio of the twenty ordinary hours, not the outlier's 4.0.
    assert_equal [ [ 12, 400.0 ] ], august.curve(:expected).points
  end

  test "places the hour where the sun stood over the house" do
    3.times { |index| pv_hour(12, 400.0, date: JULY + index) }
    3.times { |index| weather(12, solar: 0.5, date: JULY + index) }

    bin = build.map.bins.sole

    assert_equal [ 160, 55 ], [ bin.azimuth, bin.elevation ]
    assert_equal 3, bin.hours
  end

  test "draws the sun paths under the map, whatever the hours cover" do
    pv_hour(12, 400.0, date: Date.new(2025, 7, 1))

    assert_equal [ "21.6.", "21.3. / 23.9.", "21.12." ], build.map.paths.map(&:label)
  end

  test "keeps the measured curve without a location, and nothing that needs one" do
    pv_hour(12, 400.0)

    report = build(lat: nil, lon: nil)
    profile = report.profiles.sole

    assert_empty report.map.bins
    assert_empty report.map.paths
    assert_equal [ [ 12, 400.0 ] ], profile.curve(:measured).points
    assert_empty profile.curve(:theory).points
  end

  test "counts the panels of the days on which all four delivered" do
    pv_hour(12, 400.0, panels: [ 100.0, 100.0, 0.0, 0.0 ], date: JULY)
    pv_hour(12, 400.0, panels: [ 100.0, 100.0, 50.0, 50.0 ], date: JULY + 1)

    panels = build.panels

    assert_equal 1, panels.days
    assert_equal [ [ 12, 50.0 ] ], panels.curve(:pv3).points
  end

  test "reads the station's history, not its forecast of the same hour" do
    2.times { |index| pv_hour(12, 400.0, date: JULY + index) }
    2.times { |index| weather(12, solar: 0.5, date: JULY + index) }
    WeatherRecord.create!(
      kind: "forecast", daytime: "day", lat: LAT, lon: LON,
      timestamp: Time.zone.local(2026, 7, 2, 12), solar: 2.0
    )

    assert_equal [ [ 12, 400.0 ] ], build.profiles.sole.curve(:expected).points
  end

  test "calibrates only on the hours the sky was bright enough" do
    pv_hour(12, 400.0)
    weather(12, solar: 0.5)
    pv_hour(12, 900.0, date: JULY + 1)
    weather(12, solar: 0.2, date: JULY + 1)

    # The dim hour's ratio of 4.5 never calibrates; 350 W/m² average at 0.8 W per W/m².
    assert_equal [ [ 12, 280.0 ] ], build.profiles.sole.curve(:expected).points
  end

  test "still calibrates on an hour exactly at the brightness it asks for" do
    pv_hour(12, 400.0)
    weather(12, solar: 0.5)
    pv_hour(12, 600.0, date: JULY + 1)
    weather(12, solar: 0.3, date: JULY + 1)

    # 300 W/m² counts, so the best ratio is that hour's 2.0 over 400 W/m² average.
    assert_equal [ [ 12, 800.0 ] ], build.profiles.sole.curve(:expected).points
  end

  test "takes the best hour from the top of the sorted ratios" do
    21.times do |index|
      pv_hour(12, 2100.0 - (index * 100), date: JULY + index)
      weather(12, solar: 0.5, date: JULY + index)
    end

    # Ratios 0.2 to 4.2; the 95th percentile sits on 4.0, over 500 W/m² average.
    assert_equal [ [ 12, 2000.0 ] ], build.profiles.sole.curve(:expected).points
  end

  test "reads the clock in the timezone it was given" do
    pv_hour(12, 640.0)

    profile = Shading::Builder.new(location: Location.new(timezone: "UTC", lat: LAT, lon: LON)).build.profiles.sole

    assert_equal [ [ 10, 640.0 ] ], profile.curve(:measured).points
  end

  test "is empty while no PV hour has been aggregated" do
    assert build.empty?
  end

  test "has no best hour while the array produced nothing under a bright sky" do
    3.times do |index|
      pv_hour(12, 0.0, date: JULY + index)
      weather(12, solar: 0.5, date: JULY + index)
    end

    report = build

    # Nothing is scaled against a zero: no field of the sky gets a share, and
    # the expected line has nothing to convert the irradiance with.
    assert_empty report.map.bins
    assert_empty report.profiles.sole.curve(:expected).points
    assert_empty report.profiles.sole.curve(:theory).points
  end

  test "irradiance_by_time returns nothing rather than everything when there is no PV history yet" do
    weather(12, solar: 0.5) # a WeatherRecord exists, but there is no `from` to anchor the range

    result = builder.send(:irradiance_by_time, nil, Time.zone.local(2026, 7, 1, 12))

    assert_equal({}, result)
  end

  test "irradiance_by_time only reads records within the given time range" do
    weather(9, solar: 0.2)   # before the range
    weather(12, solar: 0.5)  # inside the range
    weather(15, solar: 0.8)  # after the range

    result = builder.send(:irradiance_by_time, Time.zone.local(2026, 7, 1, 11), Time.zone.local(2026, 7, 1, 13))

    assert_equal [ Time.zone.local(2026, 7, 1, 12).to_i ], result.keys
  end

  test "irradiance_by_time omits hours whose solar reading is missing" do
    weather(12, solar: nil)
    weather(13, solar: 0.5)

    result = builder.send(:irradiance_by_time, Time.zone.local(2026, 7, 1, 12), Time.zone.local(2026, 7, 1, 13))

    assert_equal [ Time.zone.local(2026, 7, 1, 13).to_i ], result.keys
  end

  test "hours lists PV hours chronologically regardless of insertion order" do
    pv_hour(18, 900.0)
    pv_hour(6, 100.0)

    times = builder.send(:hours).map(&:time)

    assert_equal times.sort, times
  end

  # Only one query to list the rows and one to join the irradiance — the
  # class comment promises "the station's whole history never has to be
  # read", which a lazily re-queried relation would quietly break.
  test "hours reads its rows with a single query, not one per first/last/each access" do
    pv_hour(6, 100.0)
    pv_hour(12, 400.0)
    weather(12, solar: 0.5)

    queries = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries += 1 unless payload[:name] == "SCHEMA"
    end
    begin
      builder.send(:hours)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_equal 2, queries
  end

  test "hours bounds the irradiance lookup by the last PV hour, not the whole station history" do
    pv_hour(6, 100.0)
    pv_hour(12, 400.0)
    instance = builder
    captured_to = :not_called

    instance.stub(:irradiance_by_time, ->(_from, to) { captured_to = to; {} }) do
      instance.send(:hours)
    end

    assert_equal Time.zone.local(JULY.year, JULY.month, JULY.day, 12), captured_to
  end

  test "paths reads the current year in the location's own zone, not the app's default" do
    captured_year = nil
    fake_sun_paths = Object.new
    fake_sun_paths.define_singleton_method(:build) { |year| captured_year = year; [] }

    Shading::SunPaths.stub(:new, fake_sun_paths) do
      # 22:00 UTC on Dec 31st is still Dec 31st in the app's own default zone
      # (Europe/Berlin, +1h) but already Jan 1st in Pacific/Auckland (+13h).
      travel_to Time.utc(2026, 12, 31, 22) do
        builder(timezone: "Pacific/Auckland").send(:paths)
      end
    end

    assert_equal 2027, captured_year
  end
end
