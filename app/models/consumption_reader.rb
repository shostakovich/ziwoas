# Reads current measured household consumption from Shelly/Fritz samples
# and computes the export-safe lower bound (guaranteed_floor_w). The two
# window aggregations are expensive at the 30s control tick, so load_estimate
# memoizes them in Rails.cache; the live sum is always read fresh.
class ConsumptionReader
  FLOOR_WINDOW_S         = 24 * 60 * 60
  MEDIAN_WINDOW_S        = 30 * 60

  FLOOR_CACHE_KEY  = "zero_export.floor_w".freeze
  MEDIAN_CACHE_KEY = "zero_export.median_w".freeze
  FLOOR_CACHE_TTL  = 1.hour
  MEDIAN_CACHE_TTL = 60.seconds

  def initialize(plugs:, now: Time.now, offline_after_s: Plugs::Measurement::OFFLINE_AFTER_S)
    roster           = Plugs::Roster.wrap(plugs)
    @consumer_plugs  = roster.consumers
    @consumer_ids    = roster.consumer_ids
    @now             = now
    @offline_after_s = offline_after_s
  end

  def load_estimate
    LoadEstimate.new(
      current_w: current_consumption_w,
      floor_w: Rails.cache.fetch(FLOOR_CACHE_KEY, expires_in: FLOOR_CACHE_TTL) { guaranteed_floor_w },
      median_w: Rails.cache.fetch(MEDIAN_CACHE_KEY, expires_in: MEDIAN_CACHE_TTL) { median_consumption_w }
    )
  end

  def current_consumption_w
    Plugs::Measurement.for(@consumer_ids, now: @now, offline_after_s: @offline_after_s).total_w
  end

  # Minimum total 5-min consumption over the last 24h. Computed from raw
  # samples because samples_5min is only built daily by the Aggregator.
  def guaranteed_floor_w
    totals = consumption_per_bucket_w(FLOOR_WINDOW_S)
    totals.empty? ? 0.0 : totals.min
  end

  # Median total 5-min consumption over the last 30 minutes. This caps short
  # live-load spikes while still letting current_consumption_w clamp downward
  # immediately after a load drop.
  def median_consumption_w
    values = consumption_per_bucket_w(MEDIAN_WINDOW_S).sort
    return nil if values.empty?

    mid = values.length / 2
    values.length.odd? ? values[mid].to_f : ((values[mid - 1] + values[mid]) / 2.0)
  end

  private

  def consumption_per_bucket_w(window_s)
    PowerSeries.from_samples(
      plugs: @consumer_plugs,
      start_ts: @now.to_i - window_s,
      end_ts: @now.to_i + 1,
      bucket_seconds: PowerSeries::SAMPLE_5MIN_BUCKET_SECONDS
    ).each_bucket.map(&:consumption_w)
  end
end
