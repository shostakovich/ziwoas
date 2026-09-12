require "test_helper"
require "aggregator"
require "tzinfo"
require "fileutils"
require "tmpdir"

class AggregatorTest < ActiveSupport::TestCase
  cover "Aggregator*"

  self.use_transactional_tests = false

  setup do
    Plugs::Sample.delete_all
    Plugs::Sample5min.delete_all
    Plugs::DailyTotal.delete_all
    DailyEnergySummary.delete_all

    @tz         = TZInfo::Timezone.get("Europe/Berlin")
    @aggregator = Aggregator.new(timezone: @tz, raw_retention_days: 7)
  end

  # Local Europe/Berlin date "2026-04-10" = 2026-04-10 00:00 Berlin = 22:00 UTC previous day
  def berlin_midnight_utc(date_s)
    @tz.local_to_utc(Time.parse("#{date_s} 00:00:00")).to_i
  end

  def seed_day(plug_id:, date:, start_energy:, end_energy:, start_power: 0, end_power: 0)
    start_ts = berlin_midnight_utc(date)
    (0..23).each do |h|
      ratio = h / 23.0
      Plugs::Sample.create!(
        plug_id:    plug_id,
        ts:         start_ts + h * 3600,
        apower_w:   start_power  + (end_power  - start_power)  * ratio,
        aenergy_wh: start_energy + (end_energy - start_energy) * ratio
      )
    end
  end

  test "daily total is energy delta" do
    seed_day(plug_id: "bkw", date: "2026-04-10", start_energy: 1000.0, end_energy: 1800.0)
    @aggregator.aggregate_day("2026-04-10")
    row = Plugs::DailyTotal.find_by!(plug_id: "bkw", date: "2026-04-10")
    assert_in_delta 800.0, row.energy_wh
  end

  test "aggregate_day writes 5-minute samples" do
    start_ts = berlin_midnight_utc("2026-04-10")
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 0, apower_w: 10, aenergy_wh: 100)
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 60, apower_w: 20, aenergy_wh: 103)
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 300, apower_w: 40, aenergy_wh: 110)

    @aggregator.aggregate_day("2026-04-10")

    rows = ActiveRecord::Base.connection.exec_query(
      "SELECT plug_id, bucket_ts, avg_power_w, energy_delta_wh, sample_count FROM samples_5min ORDER BY bucket_ts"
    ).to_a

    assert_equal 2, rows.length
    assert_equal({
      "plug_id" => "bkw",
      "bucket_ts" => start_ts,
      "avg_power_w" => 15.0,
      "energy_delta_wh" => 3.0,
      "sample_count" => 2
    }, rows.first)
    assert_equal({
      "plug_id" => "bkw",
      "bucket_ts" => start_ts + 300,
      "avg_power_w" => 40.0,
      "energy_delta_wh" => 7.0,
      "sample_count" => 1
    }, rows.second)
  end

  test "daily total handles meter reset" do
    start_ts = berlin_midnight_utc("2026-04-10")

    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts,        apower_w: 0, aenergy_wh: 424_440.0)
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 3600, apower_w: 0, aenergy_wh: 424_440.0)
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 7200, apower_w: 0, aenergy_wh: 0.0)
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 7260, apower_w: 0, aenergy_wh: 100.0)

    @aggregator.aggregate_day("2026-04-10")

    row = Plugs::DailyTotal.find_by!(plug_id: "bkw", date: "2026-04-10")
    assert_in_delta 100.0, row.energy_wh
  end

  test "daily total ignores glitch zero then jump back" do
    start_ts = berlin_midnight_utc("2026-04-10")

    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts,      apower_w: 145, aenergy_wh: 425_000.0)
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 5,  apower_w: 145, aenergy_wh: 0.0)
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 10, apower_w: 145, aenergy_wh: 425_005.0)
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 15, apower_w: 145, aenergy_wh: 425_010.0)

    @aggregator.aggregate_day("2026-04-10")

    row = Plugs::DailyTotal.find_by!(plug_id: "bkw", date: "2026-04-10")
    assert_in_delta 5.0, row.energy_wh
  end

  test "aggregate_day is idempotent" do
    seed_day(plug_id: "bkw", date: "2026-04-10",
             start_power: 50, end_power: 50, start_energy: 0, end_energy: 1200)
    @aggregator.aggregate_day("2026-04-10")
    first_count_5min = Plugs::Sample5min.count
    first_total = Plugs::DailyTotal.first.energy_wh
    @aggregator.aggregate_day("2026-04-10")
    assert_equal first_count_5min, Plugs::Sample5min.count
    assert_in_delta first_total, Plugs::DailyTotal.first.energy_wh
    assert_equal 1, Plugs::DailyTotal.count
  end

  test "purge deletes samples older than retention" do
    old_ts   = Time.now.to_i - 10 * 86_400
    fresh_ts = Time.now.to_i - 1 * 86_400
    Plugs::Sample.create!(plug_id: "bkw", ts: old_ts,   apower_w: 1, aenergy_wh: 1)
    Plugs::Sample.create!(plug_id: "bkw", ts: fresh_ts, apower_w: 2, aenergy_wh: 2)
    @aggregator.purge_old_raw!
    assert_equal [ fresh_ts ], Plugs::Sample.pluck(:ts)
  end

  test "initialize defaults raw_retention_days to seven days" do
    aggregator = Aggregator.new(timezone: @tz)
    kept_ts    = Time.now.to_i - 6 * 86_400
    purged_ts  = Time.now.to_i - 8 * 86_400
    Plugs::Sample.create!(plug_id: "bkw", ts: kept_ts,   apower_w: 1, aenergy_wh: 1)
    Plugs::Sample.create!(plug_id: "bkw", ts: purged_ts, apower_w: 1, aenergy_wh: 1)

    aggregator.purge_old_raw!

    assert_equal [ kept_ts ], Plugs::Sample.pluck(:ts)
  end

  # The day window must come from the Aggregator's own configured zone, not
  # the suite's Europe/Berlin Time.zone default.
  test "aggregate_day computes the day window in the configured timezone, not the global default" do
    aggregator = Aggregator.new(timezone: TZInfo::Timezone.get("America/New_York"), raw_retention_days: 7)
    # America/New_York midnight May 1st is 04:00 UTC. Two samples an hour
    # before that must stay outside the day, but would fall inside it under
    # the suite's Europe/Berlin default (starts 22:00 UTC April 30th).
    Plugs::Sample.create!(plug_id: "bkw", ts: Time.utc(2026, 5, 1, 2).to_i, apower_w: 0, aenergy_wh: 100.0)
    Plugs::Sample.create!(plug_id: "bkw", ts: Time.utc(2026, 5, 1, 3).to_i, apower_w: 0, aenergy_wh: 200.0)

    aggregator.aggregate_day("2026-05-01")

    assert_equal 0, Plugs::Sample5min.count
    assert_nil Plugs::DailyTotal.find_by(plug_id: "bkw", date: "2026-05-01")
  end

  test "aggregate_day clears exactly the requested day's 5-minute samples, not more or less" do
    start_ts = berlin_midnight_utc("2026-04-10")
    end_ts   = berlin_midnight_utc("2026-04-11")

    Plugs::Sample5min.create!(plug_id: "bkw", bucket_ts: start_ts - 300, avg_power_w: 1, energy_delta_wh: 1, sample_count: 1)
    Plugs::Sample5min.create!(plug_id: "bkw", bucket_ts: end_ts - 1,     avg_power_w: 1, energy_delta_wh: 1, sample_count: 1)
    Plugs::Sample5min.create!(plug_id: "bkw", bucket_ts: end_ts,         avg_power_w: 1, energy_delta_wh: 1, sample_count: 1)

    @aggregator.aggregate_day("2026-04-10")

    remaining = Plugs::Sample5min.where(plug_id: "bkw").pluck(:bucket_ts)
    assert_includes remaining, start_ts - 300, "a bucket from the previous day must survive"
    assert_includes remaining, end_ts,         "a bucket from the next day must survive"
    refute_includes remaining, end_ts - 1,     "the last bucket of the requested day must be cleared"
  end

  test "aggregate_day only clears the requested day's daily_energy_summary row" do
    plugs = [ ConfigLoader::PlugCfg.new(id: "bkw", name: "BKW", role: :producer, driver: :shelly, ain: nil) ]
    aggregator = Aggregator.new(timezone: @tz, raw_retention_days: 7, plugs: plugs)
    DailyEnergySummary.create!(date: "2026-01-01", produced_wh: 1.0, consumed_wh: 1.0, self_consumed_wh: 1.0)
    seed_day(plug_id: "bkw", date: "2026-04-10", start_energy: 0.0, end_energy: 100.0)

    aggregator.aggregate_day("2026-04-10")

    assert DailyEnergySummary.find_by(date: "2026-01-01"), "an unrelated day's summary must survive"
  end

  test "aggregate_day with no samples does not raise" do
    @aggregator.aggregate_day("1999-01-01")
    assert_equal 0, Plugs::DailyTotal.count
  end

  test "backup creates sqlite file" do
    Dir.mktmpdir do |tmp|
      Plugs::Sample.create!(plug_id: "bkw", ts: 1, apower_w: 0, aenergy_wh: 0)
      backup_dir = File.join(tmp, "backup")
      @aggregator.backup!(backup_dir)

      files = Dir.glob("#{backup_dir}/*.db")
      assert_equal 1, files.length
      assert_match(/ziwoas-\d{4}-\d{2}-\d{2}\.db\z/, files.first)
      assert File.size(files.first) > 0
    end
  end

  test "backup keeps only 7 most recent" do
    Dir.mktmpdir do |tmp|
      backup_dir = File.join(tmp, "backup")
      FileUtils.mkdir_p(backup_dir)

      10.times do |i|
        path = File.join(backup_dir, "ziwoas-2026-04-#{format('%02d', i + 1)}.db")
        File.write(path, "fake#{i}")
        File.utime(Time.now - (10 - i) * 86_400, Time.now - (10 - i) * 86_400, path)
      end

      @aggregator.backup!(backup_dir)

      remaining = Dir.glob("#{backup_dir}/*.db").map { |f| File.basename(f) }.sort
      assert_equal 7, remaining.length
      assert remaining.any? { |f| f.include?(Date.today.to_s) }
    end
  end

  test "run_once with no samples returns without error" do
    assert_nothing_raised { @aggregator.run_once }
    assert_equal 0, Plugs::DailyTotal.count
  end

  test "run_once skips days already in daily_totals" do
    seed_day(plug_id: "bkw", date: "2026-04-10", start_energy: 0, end_energy: 800)
    @aggregator.aggregate_day("2026-04-10")
    count_before = Plugs::DailyTotal.count

    @aggregator.run_once(today: Date.new(2026, 4, 11))
    assert_equal count_before, Plugs::DailyTotal.count
  end

  test "run_once aggregates missing days up to yesterday" do
    seed_day(plug_id: "bkw", date: "2026-04-10", start_energy: 0, end_energy: 800)
    seed_day(plug_id: "bkw", date: "2026-04-11", start_energy: 800, end_energy: 1600)

    @aggregator.run_once(today: Date.new(2026, 4, 12))
    assert_equal 2, Plugs::DailyTotal.count
    assert Plugs::DailyTotal.find_by(plug_id: "bkw", date: "2026-04-10")
    assert Plugs::DailyTotal.find_by(plug_id: "bkw", date: "2026-04-11")
  end

  test "purge_old_raw! preserves records within retention window" do
    now = Time.now.to_i
    Plugs::Sample.create!(plug_id: "bkw", ts: now - 3 * 86_400, apower_w: 1, aenergy_wh: 1)
    @aggregator.purge_old_raw!
    assert_equal 1, Plugs::Sample.count
  end

  test "aggregate_day writes daily_energy_summary row" do
    plugs = [
      ConfigLoader::PlugCfg.new(id: "bkw",    name: "BKW",    role: :producer, driver: :shelly, ain: nil),
      ConfigLoader::PlugCfg.new(id: "fridge", name: "Fridge", role: :consumer, driver: :shelly, ain: nil)
    ]
    aggregator = Aggregator.new(timezone: @tz, raw_retention_days: 7, plugs: plugs)

    start_ts = berlin_midnight_utc("2026-04-10")
    # 1 hour of producer 200W and consumer 100W simultaneously, sampled every minute
    (0..3600).step(60) do |dt|
      Plugs::Sample.create!(plug_id: "bkw",    ts: start_ts + dt, apower_w: 200.0, aenergy_wh: 200.0 * dt / 3600.0)
      Plugs::Sample.create!(plug_id: "fridge", ts: start_ts + dt, apower_w: 100.0, aenergy_wh: 100.0 * dt / 3600.0)
    end

    aggregator.aggregate_day("2026-04-10")

    summary = DailyEnergySummary.find("2026-04-10")
    assert_in_delta 200.0, summary.produced_wh,      1.0
    assert_in_delta 100.0, summary.consumed_wh,      1.0
    assert_in_delta 100.0, summary.self_consumed_wh, 1.0
  end

  test "aggregate_day is idempotent for daily_energy_summary" do
    plugs = [
      ConfigLoader::PlugCfg.new(id: "bkw",    name: "BKW",    role: :producer, driver: :shelly, ain: nil),
      ConfigLoader::PlugCfg.new(id: "fridge", name: "Fridge", role: :consumer, driver: :shelly, ain: nil)
    ]
    aggregator = Aggregator.new(timezone: @tz, raw_retention_days: 7, plugs: plugs)

    start_ts = berlin_midnight_utc("2026-04-10")
    Plugs::Sample.create!(plug_id: "bkw",    ts: start_ts,         apower_w: 200, aenergy_wh: 0)
    Plugs::Sample.create!(plug_id: "bkw",    ts: start_ts + 600,   apower_w: 200, aenergy_wh: 33.3)
    Plugs::Sample.create!(plug_id: "fridge", ts: start_ts,         apower_w: 100, aenergy_wh: 0)
    Plugs::Sample.create!(plug_id: "fridge", ts: start_ts + 600,   apower_w: 100, aenergy_wh: 16.7)

    aggregator.aggregate_day("2026-04-10")
    first = DailyEnergySummary.find("2026-04-10").attributes
    aggregator.aggregate_day("2026-04-10")

    assert_equal 1, DailyEnergySummary.count
    assert_in_delta first.fetch("self_consumed_wh"), DailyEnergySummary.find("2026-04-10").self_consumed_wh, 0.01
  end

  test "aggregate_day does not write summary when plugs are not provided" do
    aggregator = Aggregator.new(timezone: @tz, raw_retention_days: 7)
    seed_day(plug_id: "bkw", date: "2026-04-10", start_energy: 1000.0, end_energy: 1800.0)

    aggregator.aggregate_day("2026-04-10")
    assert_equal 0, DailyEnergySummary.count
  end

  # Europe/Berlin 2026-10-25 is 25 hours long, 2026-03-29 only 23.
  # A fixed 86_400-second window clips the one and overruns the other.
  test "long DST day aggregates all 25 hours" do
    start_ts = 1_792_879_200 # 2026-10-25 00:00 Berlin
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 24 * 3600,        apower_w: 10, aenergy_wh: 100)
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 24 * 3600 + 1800, apower_w: 10, aenergy_wh: 150)

    @aggregator.aggregate_day("2026-10-25")

    row = Plugs::DailyTotal.find_by!(plug_id: "bkw", date: "2026-10-25")
    assert_in_delta 50.0, row.energy_wh
  end

  test "short DST day stops after 23 hours" do
    start_ts = 1_774_738_800 # 2026-03-29 00:00 Berlin
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 23 * 3600,        apower_w: 10, aenergy_wh: 100)
    Plugs::Sample.create!(plug_id: "bkw", ts: start_ts + 23 * 3600 + 1800, apower_w: 10, aenergy_wh: 150)

    @aggregator.aggregate_day("2026-03-29")

    assert_nil Plugs::DailyTotal.find_by(plug_id: "bkw", date: "2026-03-29")
  end
end
