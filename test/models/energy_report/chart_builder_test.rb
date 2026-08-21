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
