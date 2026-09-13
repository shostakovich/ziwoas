require "test_helper"

class SunCalendar::BuilderTest < ActiveSupport::TestCase
  cover "SunCalendar::Builder*"

  LAT = 52.52
  LON = 13.405
  DOY = Date.new(2026, 4, 10).yday

  MAY = Date.new(2026, 5, 10)
  MAY_DOY = MAY.yday

  setup do
    Solakon::PvHour.delete_all
    WeatherRecord.delete_all
    Plugs::Sample5min.delete_all
  end

  def plug_bucket(local_hour, energy_wh, minute: 0, date: MAY, plug_id: "bkw")
    Plugs::Sample5min.create!(
      plug_id: plug_id,
      bucket_ts: Time.zone.local(date.year, date.month, date.day, local_hour, minute).to_i,
      avg_power_w: energy_wh * 12,
      energy_delta_wh: energy_wh,
      sample_count: 10
    )
  end

  def builder(lat: LAT, lon: LON, producer_ids: [])
    SunCalendar::Builder.new(timezone: "Europe/Berlin", lat: lat, lon: lon, producer_ids: producer_ids)
  end

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

  test "averages cloud cover as a true mean, not truncated to an integer" do
    weather(11, solar: 0.4, cloud: 20)
    weather(12, solar: 0.6, cloud: 21)

    day = builder.build(2026).days.find { |candidate| candidate.doy == DOY }

    assert_in_delta 20.5, day.cloud_avg
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
    year = builder.build(2026)

    assert_equal 2026, year.year
    assert_equal 365, year.days.length
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

  test "rounds using the highest reading, not the first or last one inserted" do
    pv_hour(10, 300.0)
    pv_hour(11, 900.0)
    pv_hour(12, 500.0)

    assert_equal 900.0, builder.build(2026).strips.fetch(:pv).max
  end

  test "labels each strip with its key, title, unit and ramp" do
    pv_hour(12, 640.0)
    weather(12, solar: 0.62, cloud: 40)

    strips = builder.build(2026).strips

    assert_equal :pv, strips.fetch(:pv).key
    assert_equal "PV-Leistung", strips.fetch(:pv).title

    assert_equal :irradiance, strips.fetch(:irradiance).key
    assert_equal "Einstrahlung", strips.fetch(:irradiance).title
    assert_equal "W/m²", strips.fetch(:irradiance).unit
    assert_equal :blue, strips.fetch(:irradiance).ramp

    assert_equal :cloud, strips.fetch(:cloud).key
    assert_equal "Bewölkung", strips.fetch(:cloud).title
    assert_equal "%", strips.fetch(:cloud).unit
    assert_equal :grey, strips.fetch(:cloud).ramp
  end

  test "takes the best day's PV energy as the year's maximum, not the first or last day" do
    pv_hour(11, 100.0, date: Date.new(2026, 1, 15))
    pv_hour(11, 500.0, date: Date.new(2026, 4, 10))
    pv_hour(12, 700.0, date: Date.new(2026, 4, 10))
    pv_hour(11, 200.0, date: Date.new(2026, 11, 1))

    assert_in_delta 1.2, builder.build(2026).max_kwh
  end

  test "shows the base hours and widens them for data outside" do
    assert_equal (3..22), builder.build(2026).hours

    pv_hour(1, 5.0)
    pv_hour(23, 7.0)

    assert_equal (1..23), builder.build(2026).hours
  end

  test "fills the time before the inverter from the producer plug" do
    plug_bucket(12, 50.0)
    plug_bucket(12, 30.0, minute: 5)
    pv_hour(12, 640.0, date: Date.new(2026, 6, 20))

    year = builder(producer_ids: [ "bkw" ]).build(2026)

    assert_in_delta 80.0, year.strips.fetch(:pv).values.fetch([ MAY_DOY, 12 ])
    assert_in_delta 640.0, year.strips.fetch(:pv).values.fetch([ Date.new(2026, 6, 20).yday, 12 ])
  end

  test "counts the plug's hours into the day's PV energy" do
    plug_bucket(11, 200.0)
    plug_bucket(12, 300.0)
    pv_hour(12, 640.0, date: Date.new(2026, 6, 20))

    day = builder(producer_ids: [ "bkw" ]).build(2026).days.find { |candidate| candidate.doy == MAY_DOY }

    assert_in_delta 0.5, day.pv_kwh
  end

  test "leaves the plug out from the day the inverter took over" do
    plug_bucket(12, 50.0, date: Date.new(2026, 6, 20))
    plug_bucket(13, 90.0, date: Date.new(2026, 7, 1))
    pv_hour(12, 640.0, date: Date.new(2026, 6, 20))

    values = builder(producer_ids: [ "bkw" ]).build(2026).strips.fetch(:pv).values

    assert_equal [ [ Date.new(2026, 6, 20).yday, 12 ] ], values.keys
  end

  test "ignores plugs that do not produce" do
    plug_bucket(12, 50.0)

    assert_empty builder(producer_ids: [ "fridge" ]).build(2026).strips.fetch(:pv).values
    assert_empty builder.build(2026).strips.fetch(:pv).values
  end

  test "takes the whole plug history when no inverter ever reported" do
    plug_bucket(12, 50.0)

    year = builder(producer_ids: [ "bkw" ]).build(2026)

    assert_in_delta 50.0, year.strips.fetch(:pv).values.fetch([ MAY_DOY, 12 ])
    assert_nil year.seam
  end

  test "marks the seam at the inverter's first day" do
    plug_bucket(12, 50.0)
    pv_hour(12, 640.0, date: Date.new(2026, 6, 20))

    assert_equal Date.new(2026, 6, 20), builder(producer_ids: [ "bkw" ]).build(2026).seam
  end

  test "has no seam when the plug never stood in" do
    pv_hour(12, 640.0, date: Date.new(2026, 6, 20))

    assert_nil builder(producer_ids: [ "bkw" ]).build(2026).seam
  end

  test "widens the hours so the sun lines stay inside the strip" do
    year = SunCalendar::Builder.new(timezone: "Europe/Madrid", lat: 43.4, lon: -8.4).build(2026)

    assert_operator year.hours.first, :<=, year.lines.rise.map(&:last).min
    assert_operator year.hours.last + 1, :>=, year.lines.set.map(&:last).max
  end

  test "widens using whichever of sunrise or sunset reaches furthest, not just one" do
    # West of its zone's meridian: the extreme hour comes from sunset.
    west = SunCalendar::Builder.new(timezone: "Europe/Oslo", lat: 69.6, lon: 18.9).build(2026)
    # East of its zone's meridian: the extreme hour comes from sunrise instead.
    east = SunCalendar::Builder.new(timezone: "Europe/Oslo", lat: 69.6, lon: 40.0).build(2026)

    assert_equal (0..24), west.hours
    assert_equal (0..24), east.hours
  end

  test "keeps the base hours when the sun stays safely inside them" do
    year = SunCalendar::Builder.new(timezone: "UTC", lat: 0.0, lon: 0.0).build(2026)

    assert_equal (3..22), year.hours
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

  test "reads the PV hour's local time in the builder's own zone, not the app default" do
    # 2026-04-10 23:00 UTC is 2026-04-11 01:00 in the app's default zone (Europe/Berlin),
    # but 2026-04-10 13:00 in the builder's own zone (Pacific/Honolulu, UTC-10, no DST).
    Solakon::PvHour.create!(started_at: Time.utc(2026, 4, 10, 23, 0, 0), pv_power_w: 500.0, reading_count: 120)

    strip = SunCalendar::Builder.new(timezone: "Pacific/Honolulu").build(2026).strips.fetch(:pv)

    assert_equal({ [ Date.new(2026, 4, 10).yday, 13 ] => 500.0 }, strip.values)
  end

  test "orders PV hours chronologically so the later reading wins a repeated cell" do
    date = Date.new(2026, 10, 25)
    # Insert the chronologically LATER instant first, to prove the cell picks the winner
    # by timestamp order and not by insertion order.
    Solakon::PvHour.create!(
      started_at: Time.zone.local(date.year, date.month, date.day, 2) + 1.hour,
      pv_power_w: 300.0, reading_count: 120
    )
    pv_hour(2, 100.0, date: date)

    strip = builder.build(2026).strips.fetch(:pv)

    assert_equal 300.0, strip.values.fetch([ date.yday, 2 ])
  end

  test "reads a weather record's local time in the builder's own zone, not the app default" do
    WeatherRecord.create!(
      kind: "historic", daytime: "day", lat: 21.3, lon: -157.8,
      timestamp: Time.utc(2026, 4, 10, 23, 0, 0), solar: 0.5, cloud_cover: 40
    )

    strip = SunCalendar::Builder.new(timezone: "Pacific/Honolulu", lat: 21.3, lon: -157.8)
                                 .build(2026).strips.fetch(:irradiance)

    assert_equal [ [ Date.new(2026, 4, 10).yday, 13 ] ], strip.values.keys
  end

  test "orders weather records chronologically so the later reading wins a repeated cell" do
    date = Date.new(2026, 10, 25)
    WeatherRecord.create!(
      kind: "historic", daytime: "day", lat: LAT, lon: LON,
      timestamp: Time.zone.local(date.year, date.month, date.day, 2) + 1.hour,
      solar: 0.9, cloud_cover: 90
    )
    weather(2, solar: 0.1, cloud: 10, date: date)

    strip = builder.build(2026).strips.fetch(:irradiance)

    assert_in_delta 900.0, strip.values.fetch([ date.yday, 2 ])
  end

  test "keeps the year's start in the builder's own zone, not the app default" do
    # In the app's default zone (Europe/Berlin) both instants already fall inside 2026,
    # but only the second one sits at or after the year's start in Pacific/Honolulu (UTC-10).
    just_before_start = Time.utc(2026, 1, 1, 9, 0, 0)   # 2025-12-31 23:00 Honolulu, excluded
    at_start          = Time.utc(2026, 1, 1, 10, 0, 0)  # 2026-01-01 00:00 Honolulu, included

    Solakon::PvHour.create!(started_at: just_before_start, pv_power_w: 111.0, reading_count: 120)
    Solakon::PvHour.create!(started_at: at_start, pv_power_w: 222.0, reading_count: 120)

    strip = SunCalendar::Builder.new(timezone: "Pacific/Honolulu").build(2026).strips.fetch(:pv)

    assert_equal({ [ 1, 0 ] => 222.0 }, strip.values)
  end

  test "keeps the year's end in the builder's own zone, not the app default" do
    # In the app's default zone (Europe/Berlin) both instants already fall outside 2026,
    # but only the first one sits before the year's end in Pacific/Honolulu (UTC-10).
    last_included  = Time.utc(2027, 1, 1, 9, 59, 59) # 2026-12-31 23:59:59 Honolulu, included
    first_excluded = Time.utc(2027, 1, 1, 10, 0, 0)  # 2027-01-01 00:00:00 Honolulu, excluded

    Solakon::PvHour.create!(started_at: last_included, pv_power_w: 333.0, reading_count: 120)
    Solakon::PvHour.create!(started_at: first_excluded, pv_power_w: 444.0, reading_count: 120)

    strip = SunCalendar::Builder.new(timezone: "Pacific/Honolulu").build(2026).strips.fetch(:pv)

    assert_equal({ [ 365, 23 ] => 333.0 }, strip.values)
  end

  test "defaults to no location when lat and lon are omitted" do
    year = SunCalendar::Builder.new(timezone: "Europe/Berlin").build(2026)

    assert_predicate year.lines, :empty?
  end
end
