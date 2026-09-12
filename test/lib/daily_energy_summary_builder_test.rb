require "test_helper"
require "daily_energy_summary_builder"

class DailyEnergySummaryBuilderTest < ActiveSupport::TestCase
  cover "DailyEnergySummaryBuilder*"

  setup do
    Plugs::Sample5min.delete_all
    @plugs = [
      ConfigLoader::PlugCfg.new(id: "pv",     name: "PV",      role: :producer, driver: :shelly, ain: nil),
      ConfigLoader::PlugCfg.new(id: "desk",   name: "Desk",    role: :consumer, driver: :shelly, ain: nil),
      ConfigLoader::PlugCfg.new(id: "washer", name: "Washer",  role: :consumer, driver: :shelly, ain: nil)
    ]
    @tz = TZInfo::Timezone.get("Europe/Berlin")
    @date = "2026-04-10"
    @midnight = @tz.local_to_utc(Time.parse("#{@date} 00:00:00")).to_i
  end

  def write_5min(plug_id:, offset_min:, avg_w:)
    Plugs::Sample5min.create!(
      plug_id: plug_id,
      bucket_ts: @midnight + offset_min * 60,
      avg_power_w: avg_w,
      energy_delta_wh: avg_w * 300.0 / 3600.0,
      sample_count: 1
    )
  end

  test "returns zero for a day with no buckets" do
    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build(@date)
    assert_in_delta 0.0, result.fetch(:produced_wh)
    assert_in_delta 0.0, result.fetch(:consumed_wh)
    assert_in_delta 0.0, result.fetch(:self_consumed_wh)
  end

  test "consumer-only day yields zero self-consumption" do
    write_5min(plug_id: "desk", offset_min: 0, avg_w: 100)
    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build(@date)
    assert_in_delta 0.0,           result.fetch(:produced_wh)
    assert_in_delta 100.0 * 5/60.0, result.fetch(:consumed_wh)
    assert_in_delta 0.0,           result.fetch(:self_consumed_wh)
  end

  test "producer-only day yields zero self-consumption" do
    write_5min(plug_id: "pv", offset_min: 0, avg_w: 200)
    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build(@date)
    assert_in_delta 200.0 * 5/60.0, result.fetch(:produced_wh)
    assert_in_delta 0.0,           result.fetch(:consumed_wh)
    assert_in_delta 0.0,           result.fetch(:self_consumed_wh)
  end

  test "self-consumption is min of producer and consumer per bucket" do
    write_5min(plug_id: "pv",   offset_min: 0,  avg_w: 200)
    write_5min(plug_id: "desk", offset_min: 0,  avg_w: 100)
    write_5min(plug_id: "pv",   offset_min: 5,  avg_w:  50)
    write_5min(plug_id: "desk", offset_min: 5,  avg_w: 300)

    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build(@date)

    bucket_h = 5.0 / 60.0
    assert_in_delta (200 + 50) * bucket_h, result.fetch(:produced_wh)
    assert_in_delta (100 + 300) * bucket_h, result.fetch(:consumed_wh)
    assert_in_delta (100 +  50) * bucket_h, result.fetch(:self_consumed_wh)
  end

  test "sums multiple consumers per bucket before taking the min" do
    write_5min(plug_id: "pv",     offset_min: 0, avg_w: 250)
    write_5min(plug_id: "desk",   offset_min: 0, avg_w: 100)
    write_5min(plug_id: "washer", offset_min: 0, avg_w: 200)

    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build(@date)

    bucket_h = 5.0 / 60.0
    assert_in_delta 250 * bucket_h, result.fetch(:produced_wh)
    assert_in_delta 300 * bucket_h, result.fetch(:consumed_wh)
    assert_in_delta 250 * bucket_h, result.fetch(:self_consumed_wh)
  end

  test "ignores buckets outside the requested local day" do
    write_5min(plug_id: "pv",   offset_min: 0,         avg_w: 200)
    write_5min(plug_id: "desk", offset_min: 0,         avg_w: 100)
    write_5min(plug_id: "pv",   offset_min: 24 * 60,   avg_w: 999)

    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build(@date)

    bucket_h = 5.0 / 60.0
    assert_in_delta 200 * bucket_h, result.fetch(:produced_wh)
    assert_in_delta 100 * bucket_h, result.fetch(:consumed_wh)
    assert_in_delta 100 * bucket_h, result.fetch(:self_consumed_wh)
  end

  test "ignores buckets from before the requested local day" do
    # Just before local midnight — must not leak into the day's window.
    write_5min(plug_id: "desk", offset_min: -10, avg_w: 999)
    write_5min(plug_id: "desk", offset_min: 0,   avg_w: 120)

    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build(@date)

    assert_in_delta 120.0 * 5 / 60.0, result.fetch(:consumed_wh)
  end

  # The day window must come from the builder's own configured zone, not the
  # suite's Europe/Berlin Time.zone default.
  test "initialize computes the day window in the configured timezone, not the global default" do
    builder = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: TZInfo::Timezone.get("America/New_York"))
    # America/New_York midnight May 1st is 04:00 UTC. A bucket one hour
    # earlier must stay outside the day, but would fall inside it under the
    # suite's Europe/Berlin default (starts 22:00 UTC April 30th).
    Plugs::Sample5min.create!(
      plug_id: "desk", bucket_ts: Time.utc(2026, 5, 1, 3).to_i,
      avg_power_w: 120.0, energy_delta_wh: 120.0 * 5 / 60.0, sample_count: 1
    )

    result = builder.build("2026-05-01")

    assert_in_delta 0.0, result.fetch(:consumed_wh)
  end

  test "self-consumption uses avg_power_w even when energy_delta_wh is clipped" do
    bucket_h = 5.0 / 60.0

    # Producer counter glitched: avg_power_w is real, but the per-sample
    # plausibility cap zeroed every delta -> energy_delta_wh = 0 for the bucket.
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: @midnight, avg_power_w: 200.0,
      energy_delta_wh: 0.0, sample_count: 60
    )
    # Consumer is healthy.
    Plugs::Sample5min.create!(
      plug_id: "desk", bucket_ts: @midnight, avg_power_w: 150.0,
      energy_delta_wh: 150.0 * bucket_h, sample_count: 60
    )

    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build(@date)

    # produced_wh stays at the metered (clipped) value — that's what the
    # counter said. But self-consumption reflects the real overlap power.
    # Clamp ensures self_consumed_wh ≤ produced_wh = 0 in this degenerate case.
    assert_in_delta 0.0,           result.fetch(:produced_wh)
    assert_in_delta 150 * bucket_h, result.fetch(:consumed_wh)
    assert_in_delta 0.0,           result.fetch(:self_consumed_wh)
  end

  test "treats negative producer avg_power_w as production magnitude" do
    bucket_h = 5.0 / 60.0

    # Shelly producer plug reports apower_w with opposite sign — but
    # aenergy_wh / energy_delta_wh stay positive (monotonic counter).
    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: @midnight, avg_power_w: -200.0,
      energy_delta_wh: 200.0 * bucket_h, sample_count: 60
    )
    Plugs::Sample5min.create!(
      plug_id: "desk", bucket_ts: @midnight, avg_power_w: 150.0,
      energy_delta_wh: 150.0 * bucket_h, sample_count: 60
    )

    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build(@date)

    assert_in_delta 200 * bucket_h, result.fetch(:produced_wh)
    assert_in_delta 150 * bucket_h, result.fetch(:consumed_wh)
    # Overlap = min(|−200|, 150) * 5/60 = 12.5 Wh — must NOT be negative.
    assert_in_delta 150 * bucket_h, result.fetch(:self_consumed_wh)
    assert result.fetch(:self_consumed_wh) >= 0.0
  end

  test "self-consumption clamps to consumed when overlap power exceeds metered consumption" do
    bucket_h = 5.0 / 60.0

    Plugs::Sample5min.create!(
      plug_id: "pv", bucket_ts: @midnight, avg_power_w: 200.0,
      energy_delta_wh: 200.0 * bucket_h, sample_count: 60
    )
    # Consumer counter glitched: avg_power_w real, energy_delta_wh = 0.
    Plugs::Sample5min.create!(
      plug_id: "desk", bucket_ts: @midnight, avg_power_w: 100.0,
      energy_delta_wh: 0.0, sample_count: 60
    )

    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build(@date)

    assert_in_delta 200 * bucket_h, result.fetch(:produced_wh)
    assert_in_delta 0.0,           result.fetch(:consumed_wh)
    assert_in_delta 0.0,           result.fetch(:self_consumed_wh)
  end

  # Europe/Berlin 2026-10-25 is 25 hours long, 2026-03-29 only 23.
  # A fixed 86_400-second window clips the one and overruns the other.
  test "long DST day covers all 25 hours" do
    @midnight = 1_792_879_200 # 2026-10-25 00:00 Berlin
    write_5min(plug_id: "desk", offset_min: 24 * 60 + 10, avg_w: 120)

    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build("2026-10-25")

    assert_in_delta 120.0 * 5 / 60.0, result.fetch(:consumed_wh)
  end

  test "short DST day stops after 23 hours" do
    @midnight = 1_774_738_800 # 2026-03-29 00:00 Berlin
    write_5min(plug_id: "desk", offset_min: 23 * 60 + 10, avg_w: 120)

    result = DailyEnergySummaryBuilder.new(plugs: @plugs, timezone: @tz).build("2026-03-29")

    assert_in_delta 0.0, result.fetch(:consumed_wh)
  end
end
