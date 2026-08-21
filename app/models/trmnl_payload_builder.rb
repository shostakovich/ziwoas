class TrmnlPayloadBuilder
  BUCKET_SECONDS = 600
  BUCKETS        = 144

  def initialize(config:)
    @config = config
    @tz     = TZInfo::Timezone.get(config.timezone)
  end

  def build
    summary    = EnergySummary.new(config: @config).compute_today
    pv_kwh     = summary.produced.kwh.round(2)
    cons_kwh   = summary.consumed.kwh.round(2)
    bilanz_kwh = (summary.produced - summary.consumed).kwh.round(2)
    autarky    = (summary.autarky_ratio          * 100).round
    self_use   = (summary.self_consumption_ratio * 100).round
    pv_w, cons_w = power_series
    ts = sample_ts(*window_bounds)

    {
      "merge_variables" => {
        "ts"         => ts,
        "stand"      => @tz.utc_to_local(Time.at(ts).utc).strftime("%H:%M"),
        "pv_kwh"     => pv_kwh,
        "cons_kwh"   => cons_kwh,
        "bilanz_kwh" => bilanz_kwh,
        "autarky"    => autarky,
        "self_use"   => self_use,
        "pv_w"       => pv_w,
        "cons_w"     => cons_w
      }
    }
  end

  private

  def power_series
    start_ts, end_ts = window_bounds

    pv   = Array.new(BUCKETS, 0.0)
    cons = Array.new(BUCKETS, 0.0)

    PowerSeries.from_samples(plugs: @config.plugs, start_ts: start_ts, end_ts: end_ts,
                             bucket_seconds: BUCKET_SECONDS).each_bucket do |bucket|
      idx = (bucket.ts - start_ts) / BUCKET_SECONDS
      next if idx < 0 || idx >= BUCKETS

      pv[idx]   += bucket.production_w
      cons[idx] += bucket.consumption_w
    end

    [ pv.map(&:round), cons.map(&:round) ]
  end

  def window_bounds
    now_utc    = Time.now.utc
    local_now  = @tz.utc_to_local(now_utc)
    minute     = (local_now.min / 10) * 10
    slot_floor = Time.new(local_now.year, local_now.month, local_now.day, local_now.hour, minute, 0)
    end_ts     = @tz.local_to_utc(slot_floor).to_i + BUCKET_SECONDS
    start_ts   = end_ts - BUCKETS * BUCKET_SECONDS
    [ start_ts, end_ts ]
  end

  def sample_ts(start_ts, end_ts)
    plug_ids = @config.plugs.map(&:id)
    return Time.now.to_i if plug_ids.empty?

    max_ts = Plugs::Sample.where(plug_id: plug_ids, ts: start_ts...end_ts).maximum(:ts)
    max_ts || Time.now.to_i
  end
end
