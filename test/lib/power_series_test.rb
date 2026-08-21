require "test_helper"

class PowerSeriesTest < ActiveSupport::TestCase
  cover "PowerSeries*"

  BUCKET_H = 5.0 / 60.0

  setup do
    Plugs::Sample.delete_all
    Plugs::Sample5min.delete_all
    @plugs = [
      ConfigLoader::PlugCfg.new(id: "pv",     name: "PV",     role: :producer, driver: :shelly, ain: nil),
      ConfigLoader::PlugCfg.new(id: "desk",   name: "Desk",   role: :consumer, driver: :shelly, ain: nil),
      ConfigLoader::PlugCfg.new(id: "washer", name: "Washer", role: :consumer, driver: :shelly, ain: nil)
    ]
    @tz       = TZInfo::Timezone.get("Europe/Berlin")
    @midnight = @tz.local_to_utc(Time.parse("2026-04-10 00:00:00")).to_i
    @end_ts   = @midnight + 86_400
  end

  # Writes the same bucket to both sources: one pre-aggregated Plugs::Sample5min row,
  # and two raw samples whose average is avg_w.
  def write_bucket(plug_id:, offset_min:, avg_w:)
    bucket_ts = @midnight + offset_min * 60
    Plugs::Sample5min.create!(
      plug_id: plug_id, bucket_ts: bucket_ts, avg_power_w: avg_w,
      energy_delta_wh: avg_w.abs * BUCKET_H, sample_count: 2
    )
    Plugs::Sample.create!(plug_id: plug_id, ts: bucket_ts +  10, apower_w: avg_w - 50, aenergy_wh: 0.0)
    Plugs::Sample.create!(plug_id: plug_id, ts: bucket_ts + 200, apower_w: avg_w + 50, aenergy_wh: 0.0)
  end

  def each_source
    {
      "from_5min"    => PowerSeries.from_5min(Plugs::Sample5min.where(bucket_ts: @midnight...@end_ts).to_a, plugs: @plugs),
      "from_samples" => PowerSeries.from_samples(plugs: @plugs, start_ts: @midnight, end_ts: @end_ts, bucket_seconds: 300)
    }.each { |source, series| yield source, series }
  end

  def assert_self_consumed(expected_wh, produced_wh:, consumed_wh:)
    each_source do |source, series|
      assert_in_delta expected_wh, series.self_consumed_wh(produced_wh: produced_wh, consumed_wh: consumed_wh),
                      0.001, "self_consumed_wh via #{source}"
    end
  end

  # --- overlap, driven through both sources ---

  test "an empty series self-consumes nothing" do
    assert_self_consumed 0.0, produced_wh: 0.0, consumed_wh: 0.0
  end

  test "consumption without production self-consumes nothing" do
    write_bucket(plug_id: "desk", offset_min: 0, avg_w: 100)
    assert_self_consumed 0.0, produced_wh: 0.0, consumed_wh: 100 * BUCKET_H
  end

  test "production without consumption self-consumes nothing" do
    write_bucket(plug_id: "pv", offset_min: 0, avg_w: 200)
    assert_self_consumed 0.0, produced_wh: 200 * BUCKET_H, consumed_wh: 0.0
  end

  test "self-consumption is the per-bucket minimum of production and consumption" do
    write_bucket(plug_id: "pv",   offset_min: 0, avg_w: 200)
    write_bucket(plug_id: "desk", offset_min: 0, avg_w: 100)
    write_bucket(plug_id: "pv",   offset_min: 5, avg_w:  50)
    write_bucket(plug_id: "desk", offset_min: 5, avg_w: 300)

    assert_self_consumed (100 + 50) * BUCKET_H,
                         produced_wh: (200 + 50) * BUCKET_H,
                         consumed_wh: (100 + 300) * BUCKET_H
  end

  test "consumers are summed within a bucket before the minimum is taken" do
    write_bucket(plug_id: "pv",     offset_min: 0, avg_w: 250)
    write_bucket(plug_id: "desk",   offset_min: 0, avg_w: 100)
    write_bucket(plug_id: "washer", offset_min: 0, avg_w: 200)

    assert_self_consumed 250 * BUCKET_H,
                         produced_wh: 250 * BUCKET_H,
                         consumed_wh: 300 * BUCKET_H
  end

  test "treats negative producer avg_power_w as production magnitude" do
    write_bucket(plug_id: "pv",   offset_min: 0, avg_w: -200)
    write_bucket(plug_id: "desk", offset_min: 0, avg_w:  150)

    assert_self_consumed 150 * BUCKET_H,
                         produced_wh: 200 * BUCKET_H,
                         consumed_wh: 150 * BUCKET_H
  end

  test "self-consumption clamps to the metered production" do
    write_bucket(plug_id: "pv",   offset_min: 0, avg_w: 200)
    write_bucket(plug_id: "desk", offset_min: 0, avg_w: 150)

    assert_self_consumed 0.0, produced_wh: 0.0, consumed_wh: 150 * BUCKET_H
  end

  test "self-consumption clamps to the metered consumption" do
    write_bucket(plug_id: "pv",   offset_min: 0, avg_w: 200)
    write_bucket(plug_id: "desk", offset_min: 0, avg_w: 100)

    assert_self_consumed 0.0, produced_wh: 200 * BUCKET_H, consumed_wh: 0.0
  end

  # --- buckets ---

  test "each_bucket yields role totals in ascending ts order" do
    write_bucket(plug_id: "pv",     offset_min: 5, avg_w: -300)
    write_bucket(plug_id: "desk",   offset_min: 5, avg_w:  120)
    write_bucket(plug_id: "washer", offset_min: 5, avg_w:   80)
    write_bucket(plug_id: "pv",     offset_min: 0, avg_w:  100)

    each_source do |source, series|
      buckets = series.each_bucket.to_a

      assert_equal [ @midnight, @midnight + 300 ], buckets.map(&:ts), "bucket order via #{source}"
      assert_in_delta 100.0, buckets.first.production_w,  0.001, source
      assert_in_delta 0.0,   buckets.first.consumption_w, 0.001, source
      assert_in_delta 300.0, buckets.last.production_w,   0.001, source
      assert_in_delta 200.0, buckets.last.consumption_w,  0.001, source
    end
  end

  test "each_bucket with a block returns the series" do
    write_bucket(plug_id: "pv", offset_min: 0, avg_w: 100)

    each_source do |source, series|
      seen = []
      assert_same series, series.each_bucket { |bucket| seen << bucket.ts }, source
      assert_equal [ @midnight ], seen, source
    end
  end

  test "consumption_w keeps a negative reading instead of taking its magnitude" do
    write_bucket(plug_id: "desk", offset_min: 0, avg_w: -100)

    each_source do |source, series|
      assert_in_delta(-100.0, series.each_bucket.first.consumption_w, 0.001, source)
    end
  end

  test "bucket totals keep fractional watts instead of rounding to integers" do
    write_bucket(plug_id: "pv",   offset_min: 0, avg_w: 100.5)
    write_bucket(plug_id: "desk", offset_min: 0, avg_w: 50.25)

    each_source do |source, series|
      bucket = series.each_bucket.first
      assert_in_delta 100.5, bucket.production_w,  0.001, source
      assert_in_delta 50.25, bucket.consumption_w, 0.001, source
    end
  end

  test "buckets carry no reading for plugs outside the given plugs" do
    write_bucket(plug_id: "pv",     offset_min: 0, avg_w: 200)
    write_bucket(plug_id: "washer", offset_min: 0, avg_w: 150)

    known_plugs = @plugs.reject { |plug| plug.id == "washer" }
    series = PowerSeries.from_5min(Plugs::Sample5min.where(bucket_ts: @midnight...@end_ts).to_a, plugs: known_plugs)

    assert_in_delta 0.0, series.each_bucket.first.consumption_w
    assert_empty series.signed_watts_by_ts("washer")
  end

  # --- per-plug points ---

  test "signed_watts_by_ts flips producer sign and leaves consumers alone" do
    write_bucket(plug_id: "pv",   offset_min: 5, avg_w: -300)
    write_bucket(plug_id: "pv",   offset_min: 0, avg_w: -100)
    write_bucket(plug_id: "desk", offset_min: 0, avg_w:  120)

    each_source do |source, series|
      producer_points = series.signed_watts_by_ts("pv")

      assert_equal [ @midnight, @midnight + 300 ], producer_points.keys, "ts order via #{source}"
      assert_in_delta 100.0, producer_points[@midnight],       0.001, source
      assert_in_delta 300.0, producer_points[@midnight + 300], 0.001, source
      assert_in_delta 120.0, series.signed_watts_by_ts("desk")[@midnight], 0.001, source
    end
  end

  test "signed_watts_by_ts is empty for a plug without readings" do
    write_bucket(plug_id: "pv", offset_min: 0, avg_w: 100)

    each_source do |_source, series|
      assert_empty series.signed_watts_by_ts("desk")
    end
  end

  # --- reading the samples table ---

  test "from_samples honours the window bounds" do
    write_bucket(plug_id: "desk", offset_min: 0, avg_w: 100)
    Plugs::Sample.create!(plug_id: "desk", ts: @midnight - 60, apower_w: 999, aenergy_wh: 0.0)
    Plugs::Sample.create!(plug_id: "desk", ts: @end_ts,        apower_w: 999, aenergy_wh: 0.0)

    series = PowerSeries.from_samples(plugs: @plugs, start_ts: @midnight, end_ts: @end_ts, bucket_seconds: 300)

    assert_equal [ @midnight ], series.each_bucket.map(&:ts)
  end

  test "from_samples buckets by the requested width" do
    write_bucket(plug_id: "desk", offset_min: 0, avg_w: 100)
    write_bucket(plug_id: "desk", offset_min: 5, avg_w: 200)

    series = PowerSeries.from_samples(plugs: @plugs, start_ts: @midnight, end_ts: @end_ts, bucket_seconds: 600)

    assert_equal [ @midnight ], series.each_bucket.map(&:ts)
    assert_in_delta 150.0, series.each_bucket.first.consumption_w, 0.001
  end

  test "from_samples without plugs reads nothing" do
    write_bucket(plug_id: "desk", offset_min: 0, avg_w: 100)

    series = PowerSeries.from_samples(plugs: [], start_ts: @midnight, end_ts: @end_ts, bucket_seconds: 300)

    assert_empty series.each_bucket.to_a
    assert_in_delta 0.0, series.self_consumed_wh(produced_wh: 500.0, consumed_wh: 500.0)
  end

  test "from_samples includes a sample exactly at the window start" do
    Plugs::Sample.create!(plug_id: "desk", ts: @midnight, apower_w: 100, aenergy_wh: 0.0)

    series = PowerSeries.from_samples(plugs: @plugs, start_ts: @midnight, end_ts: @end_ts, bucket_seconds: 300)

    assert_equal [ @midnight ], series.each_bucket.map(&:ts)
  end

  test "from_samples skips the query when no plugs are given" do
    write_bucket(plug_id: "desk", offset_min: 0, avg_w: 100)

    assert_no_queries do
      PowerSeries.from_samples(plugs: [], start_ts: @midnight, end_ts: @end_ts, bucket_seconds: 300)
    end
  end

  test "bucket_ts_sql floors a timestamp to the bucket width" do
    assert_equal "(ts / 300) * 300", PowerSeries.bucket_ts_sql(300)
    assert_equal "(ts / 60) * 60",   PowerSeries.bucket_ts_sql(60)
  end

  test "bucket_ts_sql coerces a float bucket width to an integer" do
    assert_equal "(ts / 300) * 300", PowerSeries.bucket_ts_sql(300.0)
  end

  test "bucket_seconds coerces a numeric string instead of erroring" do
    series = PowerSeries.new(readings: [], plugs: @plugs, bucket_seconds: "300")

    assert_in_delta 0.0, series.self_consumed_wh(produced_wh: 0.0, consumed_wh: 0.0)
  end

  test "normalize sorts buckets numerically even when bucket_ts arrives as a string" do
    series = PowerSeries.new(
      readings: [ [ "pv", "20", 100 ], [ "pv", "9", 100 ] ],
      plugs: @plugs, bucket_seconds: 300
    )

    assert_equal [ 9, 20 ], series.each_bucket.map(&:ts)
  end

  test "normalize truncates a fractional bucket_ts string instead of raising" do
    series = PowerSeries.new(readings: [ [ "pv", "20.9", 100 ] ], plugs: @plugs, bucket_seconds: 300)

    assert_equal [ 20 ], series.each_bucket.map(&:ts)
  end

  test "normalize defaults a missing avg_power_w to zero instead of raising" do
    series = PowerSeries.new(readings: [ [ "pv", 0, nil ] ], plugs: @plugs, bucket_seconds: 300)

    assert_in_delta 0.0, series.each_bucket.first.production_w
  end

  test "normalize parses a malformed numeric avg_power_w string leniently" do
    series = PowerSeries.new(readings: [ [ "pv", 0, "42.5abc" ] ], plugs: @plugs, bucket_seconds: 300)

    assert_in_delta 42.5, series.each_bucket.first.production_w
  end
end
