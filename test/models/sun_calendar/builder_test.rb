require "test_helper"

class SunCalendar::BuilderTest < ActiveSupport::TestCase
  cover "SunCalendar::Builder*"

  LAT = 52.52
  LON = 13.405
  DOY = Date.new(2026, 4, 10).yday

  setup do
    Solakon::PvHour.delete_all
    WeatherRecord.delete_all
  end

  def builder(lat: LAT, lon: LON) = SunCalendar::Builder.new(timezone: "Europe/Berlin", lat: lat, lon: lon)

  def pv_hour(local_hour, watts, date: Date.new(2026, 4, 10))
    Solakon::PvHour.create!(
      started_at: Time.zone.local(date.year, date.month, date.day, local_hour),
      pv_power_w: watts,
      reading_count: 120
    )
  end

  def weather(local_hour, solar:, cloud:, date: Date.new(2026, 4, 10), lat: LAT, lon: LON)
    WeatherRecord.create!(
      kind: "historic", daytime: "day", lat: lat, lon: lon,
      timestamp: Time.zone.local(date.year, date.month, date.day, local_hour),
      solar: solar, cloud_cover: cloud
    )
  end

  test "puts the hourly PV mean into the cell of its local clock hour" do
    pv_hour(12, 640.0)

    strip = builder.build(2026).strips.fetch(:pv)

    assert_equal({ [ DOY, 12 ] => 640.0 }, strip.values)
    assert_equal "W", strip.unit
    assert_equal :amber, strip.ramp
  end

  test "turns the hourly means into the day's PV energy" do
    pv_hour(11, 500.0)
    pv_hour(12, 700.0)

    year = builder.build(2026)

    assert_in_delta 1.2, year.days.find { |day| day.doy == DOY }.pv_kwh
    assert_in_delta 1.2, year.max_kwh
  end

  test "reads irradiance as power per area and cloud cover as given" do
    weather(12, solar: 0.62, cloud: 40)

    strips = builder.build(2026).strips

    assert_in_delta 620.0, strips.fetch(:irradiance).values.fetch([ DOY, 12 ])
    assert_equal 40, strips.fetch(:cloud).values.fetch([ DOY, 12 ])
    assert_equal 100.0, strips.fetch(:cloud).max
  end

  test "sums the day's irradiance and averages its cloud cover" do
    weather(11, solar: 0.4, cloud: 20)
    weather(12, solar: 0.6, cloud: 80)
    weather(13, solar: nil, cloud: nil)

    day = builder.build(2026).days.find { |candidate| candidate.doy == DOY }

    assert_in_delta 1.0, day.irradiance_kwh_per_m2
    assert_in_delta 50.0, day.cloud_avg
  end

  test "leaves a day without data empty rather than at zero" do
    pv_hour(12, 640.0)

    day = builder.build(2026).days.find { |candidate| candidate.doy == DOY + 1 }

    assert_nil day.pv_kwh
    assert_nil day.irradiance_kwh_per_m2
    assert_nil day.cloud_avg
    assert_equal Date.new(2026, 4, 11), day.date
  end

  test "covers every day of the year, leap day included" do
    assert_equal 365, builder.build(2026).days.length
    assert_equal 366, builder.build(2024).days.length
  end

  test "rounds the strip maximum up to the next fifty" do
    pv_hour(12, 612.0)
    weather(12, solar: 0.81, cloud: 10)

    strips = builder.build(2026).strips

    assert_equal 650.0, strips.fetch(:pv).max
    assert_equal 850.0, strips.fetch(:irradiance).max
  end

  test "keeps a strip maximum above zero when nothing was measured" do
    assert_equal 50.0, builder.build(2026).strips.fetch(:pv).max
  end

  test "shows the base hours and widens them for data outside" do
    assert_equal (3..22), builder.build(2026).hours

    pv_hour(1, 5.0)
    pv_hour(23, 7.0)

    assert_equal (1..23), builder.build(2026).hours
  end

  test "widens the hours so the sun lines stay inside the strip" do
    year = SunCalendar::Builder.new(timezone: "Europe/Madrid", lat: 43.4, lon: -8.4).build(2026)

    assert_operator year.hours.first, :<=, year.lines.rise.map(&:last).min
    assert_operator year.hours.last + 1, :>=, year.lines.set.map(&:last).max
  end

  test "ignores hours and records outside the year" do
    pv_hour(12, 640.0, date: Date.new(2025, 12, 31))
    pv_hour(12, 640.0, date: Date.new(2027, 1, 1))
    weather(12, solar: 0.5, cloud: 10, date: Date.new(2025, 12, 31))

    year = builder.build(2026)

    assert_predicate year, :empty?
    assert_empty year.strips.fetch(:irradiance).values
  end

  test "ignores weather measured somewhere else" do
    weather(12, solar: 0.5, cloud: 10, lat: 48.1, lon: 11.6)

    assert_empty builder.build(2026).strips.fetch(:irradiance).values
  end

  test "ignores forecasts and leaves the historic record" do
    weather(12, solar: 0.62, cloud: 40)
    WeatherRecord.create!(
      kind: "forecast", daytime: "day", lat: LAT, lon: LON,
      timestamp: Time.zone.local(2026, 4, 10, 13), solar: 9.9, cloud_cover: 99
    )

    values = builder.build(2026).strips.fetch(:irradiance).values

    assert_equal [ [ DOY, 12 ] ], values.keys
  end

  test "is empty while no PV hour exists, whatever the weather" do
    weather(12, solar: 0.62, cloud: 40)

    assert_predicate builder.build(2026), :empty?
  end

  test "is not empty once a PV hour exists" do
    pv_hour(12, 640.0)

    refute_predicate builder.build(2026), :empty?
  end

  test "draws the sun lines for the configured location" do
    assert_equal 365 + 2, builder.build(2026).lines.rise.length
  end

  test "has no sun lines without a location" do
    assert_predicate builder(lat: nil, lon: nil).build(2026).lines, :empty?
  end

  test "reads weather only when a location is configured" do
    weather(12, solar: 0.62, cloud: 40)

    assert_empty builder(lat: nil, lon: nil).build(2026).strips.fetch(:irradiance).values
  end

  test "counts both repeated hours of the autumn clock change into the day" do
    pv_hour(2, 100.0, date: Date.new(2026, 10, 25))
    Solakon::PvHour.create!(
      started_at: Time.zone.local(2026, 10, 25, 2) + 1.hour,
      pv_power_w: 300.0, reading_count: 120
    )

    day = builder.build(2026).days.find { |candidate| candidate.doy == Date.new(2026, 10, 25).yday }

    assert_in_delta 0.4, day.pv_kwh
  end
end
