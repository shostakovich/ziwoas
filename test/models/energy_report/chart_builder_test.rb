require "test_helper"

class EnergyReport::ChartBuilderTest < ActiveSupport::TestCase
  cover "EnergyReport::ChartBuilder*"
  cover "EnergyReport::DailyPoint*"

  setup do
    Plugs::DailyTotal.delete_all
    Plugs::Sample5min.delete_all

    @plugs = [
      ConfigLoader::PlugCfg.new(id: "pv",     name: "Balkonkraftwerk", role: :producer, driver: :shelly, ain: nil),
      ConfigLoader::PlugCfg.new(id: "desk",   name: "Schreibtisch",    role: :consumer, driver: :shelly, ain: nil),
      ConfigLoader::PlugCfg.new(id: "washer", name: "Waschmaschine",   role: :consumer, driver: :shelly, ain: nil)
    ]
    @timezone = TZInfo::Timezone.get("Europe/Berlin")
    @builder  = EnergyReport::ChartBuilder.new(plugs: @plugs, timezone: @timezone, store: EnergyReport::Store.new)
  end

  def midnight_utc(date_s)
    @timezone.local_to_utc(Time.parse("#{date_s} 00:00:00")).to_i
  end

  def write_5min(plug_id:, date_s:, offset_min:, avg_w:)
    Plugs::Sample5min.create!(
      plug_id: plug_id, bucket_ts: midnight_utc(date_s) + offset_min * 60,
      avg_power_w: avg_w, energy_delta_wh: avg_w.abs * 5 / 60.0, sample_count: 1
    )
  end

  def daily_point(date_s, produced_kwh: 0.0, consumed_kwh: 0.0, self_consumed_kwh: 0.0, covered: true)
    EnergyReport::DailyPoint.new(
      date: date_s,
      produced: Energy.kwh(produced_kwh),
      consumed: Energy.kwh(consumed_kwh),
      self_consumed: Energy.kwh(self_consumed_kwh),
      covered: covered
    )
  end

  def payload_for(daily_points:, rows:, start_date:, end_date:, detail_start: nil, detail_end: nil)
    @builder.payload(
      daily_points: daily_points,
      rows: rows,
      range: { start_date: start_date, end_date: end_date },
      detail_range: { start_date: detail_start || start_date, end_date: detail_end || end_date }
    )
  end

  # --- detail chart from 5-min buckets (range of at most seven days) ---

  test "sample detail chart reports producer power as a positive magnitude" do
    write_5min(plug_id: "pv",   date_s: "2026-04-10", offset_min: 0, avg_w: -240.0)
    write_5min(plug_id: "desk", date_s: "2026-04-10", offset_min: 0, avg_w:  120.0)

    detail = payload_for(
      daily_points: [ daily_point("2026-04-10") ], rows: [],
      start_date: Date.new(2026, 4, 10), end_date: Date.new(2026, 4, 10)
    ).fetch(:detail)

    assert_equal "line", detail.fetch(:chart_type)
    assert_equal [ 240.0 ], series_data(detail, "pv")
    assert_equal [ 120.0 ], series_data(detail, "desk")
  end

  test "sample detail chart leaves a gap where a plug has no bucket" do
    write_5min(plug_id: "pv",   date_s: "2026-04-10", offset_min: 0, avg_w: -240.0)
    write_5min(plug_id: "desk", date_s: "2026-04-10", offset_min: 5, avg_w:  120.0)

    detail = payload_for(
      daily_points: [ daily_point("2026-04-10") ], rows: [],
      start_date: Date.new(2026, 4, 10), end_date: Date.new(2026, 4, 10)
    ).fetch(:detail)

    assert_equal [ 240.0, nil ], series_data(detail, "pv")
    assert_equal [ nil, 120.0 ], series_data(detail, "desk")
  end

  test "sample detail chart drops plugs without any bucket" do
    write_5min(plug_id: "pv", date_s: "2026-04-10", offset_min: 0, avg_w: -240.0)

    detail = payload_for(
      daily_points: [ daily_point("2026-04-10") ], rows: [],
      start_date: Date.new(2026, 4, 10), end_date: Date.new(2026, 4, 10)
    ).fetch(:detail)

    assert_equal [ "pv" ], detail.fetch(:series).map { |series| series.fetch(:plug_id) }
  end

  test "sample detail chart excludes buckets from outside the requested day" do
    write_5min(plug_id: "pv", date_s: "2026-04-10", offset_min: 0, avg_w: -240.0)
    # Adjacent day noise — must not leak into a single-day detail window.
    write_5min(plug_id: "pv", date_s: "2026-04-11", offset_min: 0, avg_w: -999.0)

    detail = payload_for(
      daily_points: [ daily_point("2026-04-10") ], rows: [],
      start_date: Date.new(2026, 4, 10), end_date: Date.new(2026, 4, 10)
    ).fetch(:detail)

    assert_equal [ 240.0 ], series_data(detail, "pv")
  end

  # `local_midnight_utc` window boundaries must come from the ChartBuilder's
  # own configured zone, not the suite's Europe/Berlin Time.zone default.
  test "sample detail chart window boundaries use the configured timezone, not the global default" do
    builder = EnergyReport::ChartBuilder.new(
      plugs: @plugs, timezone: TZInfo::Timezone.get("America/New_York"), store: EnergyReport::Store.new
    )
    # America/New_York midnight on May 1st is 04:00 UTC. A bucket one hour
    # earlier must stay outside that day's window, but would fall inside it
    # under the suite's Europe/Berlin default (starts 22:00 UTC April 30th).
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: Time.utc(2026, 5, 1, 3).to_i,
      avg_power_w: -240.0, energy_delta_wh: 20.0, sample_count: 1
    )

    detail = builder.payload(
      daily_points: [ daily_point("2026-05-01") ], rows: [],
      range: { start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 1) },
      detail_range: { start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 1) }
    ).fetch(:detail)

    assert_equal [], detail.fetch(:series)
  end

  # `detail_label` must format timestamps in the ChartBuilder's own
  # configured zone (America/New_York here), not the suite's Europe/Berlin
  # Time.zone default — the two would otherwise silently agree.
  test "sample detail chart labels format time as HH:MM within a single day, in the configured timezone" do
    builder = EnergyReport::ChartBuilder.new(
      plugs: @plugs, timezone: TZInfo::Timezone.get("America/New_York"), store: EnergyReport::Store.new
    )
    # 16:00 / 16:05 UTC is 12:00 / 12:05 EDT.
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: Time.utc(2026, 5, 1, 16, 0).to_i,
      avg_power_w: -240.0, energy_delta_wh: 20.0, sample_count: 1
    )
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: Time.utc(2026, 5, 1, 16, 5).to_i,
      avg_power_w: -240.0, energy_delta_wh: 20.0, sample_count: 1
    )

    detail = builder.payload(
      daily_points: [ daily_point("2026-05-01") ], rows: [],
      range: { start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 1) },
      detail_range: { start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 1) }
    ).fetch(:detail)

    assert_equal [ "12:00", "12:05" ], detail.fetch(:labels)
  end

  test "sample detail chart labels format time as DD.MM. HH:MM across multiple days, in the configured timezone" do
    builder = EnergyReport::ChartBuilder.new(
      plugs: @plugs, timezone: TZInfo::Timezone.get("America/New_York"), store: EnergyReport::Store.new
    )
    # 16:00 UTC is 12:00 EDT on both days.
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: Time.utc(2026, 5, 1, 16, 0).to_i,
      avg_power_w: -240.0, energy_delta_wh: 20.0, sample_count: 1
    )
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: Time.utc(2026, 5, 2, 16, 0).to_i,
      avg_power_w: -240.0, energy_delta_wh: 20.0, sample_count: 1
    )

    detail = builder.payload(
      daily_points: [ daily_point("2026-05-01"), daily_point("2026-05-02") ], rows: [],
      range: { start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 2) },
      detail_range: { start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 2) }
    ).fetch(:detail)

    assert_equal [ "01.05. 12:00", "02.05. 12:00" ], detail.fetch(:labels)
  end

  # `detail_icons_one_per_day` picks the icon for exactly the bucket that
  # lands on local noon, in the ChartBuilder's own configured zone — and
  # only when a matching weather hour actually exists.
  test "multi-day detail weather overlay places one icon only at local noon, only where weather exists" do
    weather_loader = Struct.new(:hourly_points) do
      def hourly(_start_date, _end_date) = hourly_points
      def daily(_start_date, _end_date) = {}
    end.new(
      [
        # 11:00 EDT — must be ignored: not noon, even though weather exists for it.
        { ts: Time.utc(2026, 5, 1, 15).to_i, solar_w_per_m2: 100.0, asset_name: "eleven.webp", alt: "cloudy" },
        # 12:00 EDT on day 1 — the one bucket that should get an icon.
        { ts: Time.utc(2026, 5, 1, 16).to_i, solar_w_per_m2: 400.0, asset_name: "day1.webp",   alt: "clear-day" }
        # Day 2's noon hour is deliberately missing weather data.
      ]
    )
    builder = EnergyReport::ChartBuilder.new(
      plugs: @plugs, timezone: TZInfo::Timezone.get("America/New_York"),
      store: EnergyReport::Store.new, weather_loader: weather_loader
    )
    # index 0: 11:00 EDT, not noon.
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: Time.utc(2026, 5, 1, 15, 0).to_i,
      avg_power_w: -240.0, energy_delta_wh: 20.0, sample_count: 1
    )
    # index 1: 12:00 EDT, noon — the one that should carry an icon.
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: Time.utc(2026, 5, 1, 16, 0).to_i,
      avg_power_w: -240.0, energy_delta_wh: 20.0, sample_count: 1
    )
    # index 2: 12:05 EDT, noon hour but wrong minute.
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: Time.utc(2026, 5, 1, 16, 5).to_i,
      avg_power_w: -240.0, energy_delta_wh: 20.0, sample_count: 1
    )
    # index 3: day 2, 12:00 EDT, noon — but no weather data for this hour.
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: Time.utc(2026, 5, 2, 16, 0).to_i,
      avg_power_w: -240.0, energy_delta_wh: 20.0, sample_count: 1
    )

    detail = builder.payload(
      daily_points: [ daily_point("2026-05-01"), daily_point("2026-05-02") ], rows: [],
      range: { start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 2) },
      detail_range: { start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 2) }
    ).fetch(:detail)

    assert_equal(
      [ { label_index: 1, asset_name: "day1.webp", alt: "clear-day" } ],
      detail.fetch(:weather).fetch(:icons)
    )
  end

  # The weather point must be looked up by its containing hour bucket, not
  # by the exact bucket timestamp — otherwise a half-hour-offset zone (whose
  # local noon does not land on a UTC hour boundary) would never match.
  test "multi-day detail weather overlay looks up the containing hour, not the exact timestamp" do
    weather_loader = Struct.new(:hourly_points) do
      def hourly(_start_date, _end_date) = hourly_points
      def daily(_start_date, _end_date) = {}
    end.new(
      [ { ts: Time.utc(2026, 5, 1, 6).to_i, solar_w_per_m2: 300.0, asset_name: "india.webp", alt: "haze" } ]
    )
    builder = EnergyReport::ChartBuilder.new(
      plugs: @plugs, timezone: TZInfo::Timezone.get("Asia/Kolkata"),
      store: EnergyReport::Store.new, weather_loader: weather_loader
    )
    # 06:30 UTC is 12:00 IST (UTC+5:30) — noon, but not on a UTC hour boundary.
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: Time.utc(2026, 5, 1, 6, 30).to_i,
      avg_power_w: -240.0, energy_delta_wh: 20.0, sample_count: 1
    )

    detail = builder.payload(
      daily_points: [ daily_point("2026-05-01"), daily_point("2026-05-02") ], rows: [],
      range: { start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 2) },
      detail_range: { start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 2) }
    ).fetch(:detail)

    assert_equal(
      [ { label_index: 0, asset_name: "india.webp", alt: "haze" } ],
      detail.fetch(:weather).fetch(:icons)
    )
  end

  # --- detail chart from daily totals (range longer than seven days) ---

  test "daily detail chart averages the metered day over 24 hours" do
    rows = [
      Plugs::DailyTotal.create!(plug_id: "pv",   date: "2026-04-10", energy_wh: 2400.0),
      Plugs::DailyTotal.create!(plug_id: "desk", date: "2026-04-10", energy_wh: 240.0)
    ]

    detail = payload_for(
      daily_points: [], rows: rows,
      start_date: Date.new(2026, 4, 4), end_date: Date.new(2026, 4, 11),
      detail_start: Date.new(2026, 4, 10), detail_end: Date.new(2026, 4, 17)
    ).fetch(:detail)

    assert_equal "bar", detail.fetch(:chart_type)
    assert_equal 100.0, series_data(detail, "pv").first
    assert_equal 10.0,  series_data(detail, "desk").first
  end

  # --- daily bar chart ---

  test "daily chart carries per-day ratios and nils the uncovered days" do
    daily = payload_for(
      daily_points: [
        daily_point("2026-04-10", produced_kwh: 2.0, consumed_kwh: 1.0, self_consumed_kwh: 0.5),
        daily_point("2026-04-11", covered: false)
      ],
      rows: [],
      start_date: Date.new(2026, 4, 10), end_date: Date.new(2026, 4, 11)
    ).fetch(:daily)

    assert_equal [ "10.04.", "11.04." ], daily.fetch(:labels)
    assert_equal [ 2.0, 0.0 ], daily.fetch(:produced_kwh)
    assert_equal [ 1.0, 0.0 ], daily.fetch(:balance_kwh)

    covered, uncovered = daily.fetch(:ratios)
    assert_equal "2026-04-10", covered.fetch(:date)
    assert_in_delta 50.0, covered.fetch(:autarky_pct)
    assert_in_delta 25.0, covered.fetch(:self_consumption_pct)
    assert_equal "2026-04-11", uncovered.fetch(:date)
    assert_nil uncovered.fetch(:autarky_pct)
    assert_nil uncovered.fetch(:self_consumption_pct)
  end

  test "ratio percentages are rounded to one decimal place, not to a whole percent" do
    point = daily_point("2026-04-10", produced_kwh: 3.0, consumed_kwh: 6.0, self_consumed_kwh: 1.0)

    daily = payload_for(
      daily_points: [ point ], rows: [],
      start_date: Date.new(2026, 4, 10), end_date: Date.new(2026, 4, 10)
    ).fetch(:daily)

    ratio = daily.fetch(:ratios).first
    assert_in_delta 16.7, ratio.fetch(:autarky_pct),          1e-9
    assert_in_delta 33.3, ratio.fetch(:self_consumption_pct), 1e-9
  end

  test "daily kwh fields are rounded to three decimals, not truncated or over-rounded" do
    point = daily_point("2026-04-10", produced_kwh: 4.567891, consumed_kwh: 2.345679)

    daily = payload_for(
      daily_points: [ point ], rows: [],
      start_date: Date.new(2026, 4, 10), end_date: Date.new(2026, 4, 10)
    ).fetch(:daily)

    assert_in_delta 4.568, daily.fetch(:produced_kwh).first, 1e-9
    assert_in_delta 2.346, daily.fetch(:consumed_kwh).first, 1e-9
    assert_in_delta 2.222, daily.fetch(:balance_kwh).first,  1e-9
  end

  test "consumer series carries each consumer's id, name and per-day kwh, defaulting missing days to zero" do
    Plugs::DailyTotal.create!(plug_id: "desk", date: "2026-04-10", energy_wh: 1234.5678)

    daily = payload_for(
      daily_points: [ daily_point("2026-04-10"), daily_point("2026-04-11") ], rows: [],
      start_date: Date.new(2026, 4, 10), end_date: Date.new(2026, 4, 11)
    ).fetch(:daily)

    assert_equal(
      [
        { plug_id: "desk",   name: "Schreibtisch",  data: [ 1.235, 0.0 ] },
        { plug_id: "washer", name: "Waschmaschine", data: [ 0.0, 0.0 ] }
      ],
      daily.fetch(:consumer_series)
    )
  end

  private

  def series_data(payload, plug_id)
    payload.fetch(:series).find { |series| series.fetch(:plug_id) == plug_id }&.fetch(:data)
  end
end
