require "test_helper"

class SolakonPvHourAggregatorTest < ActiveSupport::TestCase
  cover "Solakon::PvHourAggregator*"

  setup do
    Solakon::Reading.delete_all
    Solakon::Snapshot.delete_all
    Solakon::PvHour.delete_all
  end

  test "averages the readings of each clock hour and drops thin hours" do
    readings(local(2026, 6, 21, 10), 20) { |i| i.even? ? 100 : 200 }
    readings(local(2026, 6, 21, 11), 19) { 500 }

    aggregate(Date.new(2026, 6, 21))

    assert_equal [ local(2026, 6, 21, 10) ], Solakon::PvHour.pluck(:started_at)
    hour = Solakon::PvHour.sole
    assert_in_delta 150.0, hour.pv_power_w
    assert_equal 20, hour.reading_count
  end

  test "adds the panel means from the snapshots of the same hour" do
    readings(local(2026, 6, 21, 10), 20) { 100 }
    readings(local(2026, 6, 21, 11), 20) { 100 }
    Solakon::Snapshot.create!(taken_at: local(2026, 6, 21, 10, 1), pv1_power_w: 10, pv2_power_w: 30, pv3_power_w: nil, pv4_power_w: 0)
    Solakon::Snapshot.create!(taken_at: local(2026, 6, 21, 10, 3), pv1_power_w: 20, pv2_power_w: 50, pv3_power_w: nil, pv4_power_w: 0)

    aggregate(Date.new(2026, 6, 21))

    with_snapshots = Solakon::PvHour.find_by!(started_at: local(2026, 6, 21, 10))
    assert_in_delta 15.0, with_snapshots.pv1_power_w
    assert_in_delta 40.0, with_snapshots.pv2_power_w
    assert_nil with_snapshots.pv3_power_w
    assert_in_delta 0.0, with_snapshots.pv4_power_w

    without = Solakon::PvHour.find_by!(started_at: local(2026, 6, 21, 11))
    assert_nil without.pv1_power_w
    assert_nil without.pv4_power_w
  end

  test "rebuilds the day it aggregates and leaves other days alone" do
    Solakon::PvHour.create!(started_at: local(2026, 6, 21, 10), pv_power_w: 999, reading_count: 20)
    Solakon::PvHour.create!(started_at: local(2026, 6, 21, 12), pv_power_w: 999, reading_count: 20)
    other_day = Solakon::PvHour.create!(started_at: local(2026, 6, 22, 10), pv_power_w: 777, reading_count: 20)
    readings(local(2026, 6, 21, 10), 20) { 100 }

    aggregate(Date.new(2026, 6, 21))

    assert_equal [ local(2026, 6, 21, 10), local(2026, 6, 22, 10) ], Solakon::PvHour.order(:started_at).pluck(:started_at)
    assert_in_delta 100.0, Solakon::PvHour.find_by!(started_at: local(2026, 6, 21, 10)).pv_power_w
    assert_in_delta 777.0, other_day.reload.pv_power_w
  end

  test "follows the 25-hour day of the autumn clock change" do
    # 2026-10-25: 02:00 CEST repeats as 02:00 CET, the day ends at 23:00 UTC.
    readings(Time.utc(2026, 10, 24, 22), 20) { 1 }   # 00:00 CEST, first hour
    readings(Time.utc(2026, 10, 25, 0), 20) { 2 }    # 02:00 CEST
    readings(Time.utc(2026, 10, 25, 1), 20) { 3 }    # 02:00 CET
    readings(Time.utc(2026, 10, 25, 22), 20) { 4 }   # 23:00 CET, last hour
    readings(Time.utc(2026, 10, 25, 23), 20) { 5 }   # 00:00 CET on the 26th

    aggregate(Date.new(2026, 10, 25))

    assert_equal [ 1.0, 2.0, 3.0, 4.0 ], Solakon::PvHour.order(:started_at).pluck(:pv_power_w)
  end

  test "keeps the buckets on local clock hours in a half-hour zone" do
    Time.use_zone("Asia/Kolkata") do
      readings(local(2026, 6, 21, 10), 20) { 100 }
      Solakon::Snapshot.create!(taken_at: local(2026, 6, 21, 10, 5), pv1_power_w: 7)

      aggregate(Date.new(2026, 6, 21))

      hour = Solakon::PvHour.sole
      assert_equal Time.utc(2026, 6, 21, 4, 30), hour.started_at
      assert_in_delta 7.0, hour.pv1_power_w
    end
  end

  test "backfills two adjacent days in a half-hour zone without colliding on the midnight hour" do
    Time.use_zone("Asia/Kolkata") do
      readings(local(2026, 6, 21, 23, 45), 20) { 1 }
      readings(local(2026, 6, 22, 0, 0), 20) { 2 }

      aggregator.run_once(today: Date.new(2026, 6, 23))

      assert_equal [ [ local(2026, 6, 21, 23), 1.0 ], [ local(2026, 6, 22, 0), 2.0 ] ],
                   Solakon::PvHour.order(:started_at).pluck(:started_at, :pv_power_w)
    end
  end

  test "run_once fills every finished day since the first reading and keeps the ones it has" do
    readings(local(2026, 6, 21, 10), 20) { 100 }
    readings(local(2026, 6, 22, 10), 20) { 200 }
    readings(local(2026, 6, 23, 10), 20) { 300 }
    Solakon::PvHour.create!(started_at: local(2026, 6, 22, 15), pv_power_w: 999, reading_count: 20)

    aggregator.run_once(today: Date.new(2026, 6, 23))

    rows = Solakon::PvHour.order(:started_at).pluck(:started_at, :pv_power_w)
    assert_equal [ [ local(2026, 6, 21, 10), 100.0 ], [ local(2026, 6, 22, 15), 999.0 ] ], rows
  end

  test "run_once does nothing before the first reading" do
    aggregator.run_once(today: Date.new(2026, 6, 23))

    assert_equal 0, Solakon::PvHour.count
  end

  test "run_once defaults to today when no date is given" do
    travel_to Time.zone.local(2026, 6, 23, 12) do
      readings(local(2026, 6, 21, 10), 20) { 100 }

      aggregator.run_once

      assert_equal [ local(2026, 6, 21, 10) ], Solakon::PvHour.pluck(:started_at)
    end
  end

  test "run_once aggregates through the day immediately before today" do
    readings(local(2026, 6, 22, 10), 20) { 100 }

    aggregator.run_once(today: Date.new(2026, 6, 23))

    assert_equal [ local(2026, 6, 22, 10) ], Solakon::PvHour.pluck(:started_at)
  end

  test "aggregate_day excludes readings from the day before" do
    readings(local(2026, 6, 20, 23, 30), 20) { 999 }   # previous day, must be excluded
    readings(local(2026, 6, 21, 10), 20) { 100 }

    aggregate(Date.new(2026, 6, 21))

    assert_equal [ local(2026, 6, 21, 10) ], Solakon::PvHour.pluck(:started_at)
    assert_in_delta 100.0, Solakon::PvHour.sole.pv_power_w
  end

  test "aggregate_day excludes readings exactly at the next day's midnight" do
    # All 20 share the exact boundary instant: only a range that excludes the
    # upper bound keeps this hour below MIN_READINGS.
    20.times do
      Solakon::Reading.create!(taken_at: local(2026, 6, 22, 0), pv_power_w: 999,
                               active_power_w: 0, battery_power_w: 0, battery_soc_pct: 50)
    end

    aggregate(Date.new(2026, 6, 21))

    assert_equal 0, Solakon::PvHour.count
  end

  test "separates panel means by hour instead of averaging them together" do
    readings(local(2026, 6, 21, 10), 20) { 100 }
    readings(local(2026, 6, 21, 11), 20) { 100 }
    Solakon::Snapshot.create!(taken_at: local(2026, 6, 21, 10, 1), pv1_power_w: 10, pv2_power_w: nil, pv3_power_w: nil, pv4_power_w: nil)
    Solakon::Snapshot.create!(taken_at: local(2026, 6, 21, 11, 1), pv1_power_w: 90, pv2_power_w: nil, pv3_power_w: nil, pv4_power_w: nil)

    aggregate(Date.new(2026, 6, 21))

    assert_in_delta 10.0, Solakon::PvHour.find_by!(started_at: local(2026, 6, 21, 10)).pv1_power_w
    assert_in_delta 90.0, Solakon::PvHour.find_by!(started_at: local(2026, 6, 21, 11)).pv1_power_w
  end


  test "buckets on the zone it was given, not on the app's default" do
    # 22:00 UTC is already the 22nd in Berlin, but still the 21st in Honolulu.
    readings(Time.utc(2026, 6, 21, 22), 20) { 100 }

    aggregator(timezone: ActiveSupport::TimeZone["Pacific/Honolulu"]).aggregate_day(Date.new(2026, 6, 21))

    assert_equal [ Time.utc(2026, 6, 21, 22) ], Solakon::PvHour.pluck(:started_at)
  end

  test "panel_means only groups snapshots within the given range" do
    Solakon::Snapshot.create!(taken_at: local(2026, 6, 21, 10, 1), pv1_power_w: 10, pv2_power_w: nil, pv3_power_w: nil, pv4_power_w: nil)
    # Same clock hour, but the day before: must not be pulled into the range's grouping.
    Solakon::Snapshot.create!(taken_at: local(2026, 6, 20, 10, 1), pv1_power_w: 990, pv2_power_w: nil, pv3_power_w: nil, pv4_power_w: nil)

    day = Date.new(2026, 6, 21).in_time_zone(Time.zone)
    means = aggregator.send(:panel_means, day...(day + 1.day), day.utc_offset)

    assert_equal 1, means.size
  end

  test "run_once starts from the first reading's date in the zone it was given" do
    # 02:00 UTC on the 21st is already the 21st in plain UTC and in the app's
    # own default zone, but still the 20th in Honolulu.
    readings(Time.utc(2026, 6, 21, 2), 20) { 100 }

    aggregator(timezone: ActiveSupport::TimeZone["Pacific/Honolulu"]).run_once(today: Date.new(2026, 6, 22))

    assert_equal [ Time.utc(2026, 6, 21, 2) ], Solakon::PvHour.pluck(:started_at)
  end

  test "run_once treats a day as filled according to the zone it was given, not the app's default" do
    # 02:00 UTC on the 22nd is already the 22nd in plain UTC and the app's
    # own default zone, but still the 21st in Honolulu.
    readings(Time.utc(2026, 6, 22, 2), 20) { 100 }
    Solakon::PvHour.create!(started_at: Time.utc(2026, 6, 22, 2), pv_power_w: 999, reading_count: 20)

    aggregator(timezone: ActiveSupport::TimeZone["Pacific/Honolulu"]).run_once(today: Date.new(2026, 6, 23))

    assert_equal 999.0, Solakon::PvHour.sole.pv_power_w
  end

  test "wraps the delete and insert in a transaction so a failed insert leaves the old row intact" do
    existing = Solakon::PvHour.create!(started_at: local(2026, 6, 21, 10), pv_power_w: 111, reading_count: 20)
    readings(local(2026, 6, 21, 10), 20) { 100 }

    Solakon::PvHour.stub(:insert_all, ->(*) { raise "boom" }) do
      assert_raises(RuntimeError) { aggregate(Date.new(2026, 6, 21)) }
    end

    assert_equal 111, existing.reload.pv_power_w
  end

  private

  def aggregate(date) = aggregator.aggregate_day(date)

  def aggregator(timezone: Time.zone) = Solakon::PvHourAggregator.new(timezone: timezone)

  def local(*parts) = Time.zone.local(*parts)

  def readings(from, count)
    count.times do |i|
      Solakon::Reading.create!(taken_at: from + i * 30, pv_power_w: yield(i),
                               active_power_w: 0, battery_power_w: 0, battery_soc_pct: 50)
    end
  end
end
