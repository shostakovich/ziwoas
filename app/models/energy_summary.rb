class EnergySummary
  MAX_PLAUSIBLE_W = EnergyDeltas::MAX_PLAUSIBLE_W

  attr_reader :produced_wh, :consumed_wh, :self_consumed_wh, :savings_eur, :date

  def initialize(config:)
    @config     = config
    @tz         = TZInfo::Timezone.get(config.timezone)
    @calculator = SavingsCalculator.new(price_eur_per_kwh: config.electricity_price_eur_per_kwh)
  end

  def compute_today
    start_ts, end_ts, today = today_bounds_utc
    @produced_wh      = energy_delta_wh(producer_ids, start_ts, end_ts)
    @consumed_wh      = energy_delta_wh(consumer_ids, start_ts, end_ts)
    @self_consumed_wh = today_power_series(start_ts, end_ts)
                          .self_consumed_wh(produced_wh: @produced_wh, consumed_wh: @consumed_wh)
    @savings_eur      = @calculator.savings_eur(@produced_wh)
    @date             = today.to_s
    self
  end

  def autarky_ratio
    return 0.0 if @consumed_wh.nil? || @consumed_wh.zero?
    @self_consumed_wh / @consumed_wh
  end

  def self_consumption_ratio
    return 0.0 if @produced_wh.nil? || @produced_wh.zero?
    @self_consumed_wh / @produced_wh
  end

  private

  def today_bounds_utc
    now_utc     = Time.now.utc
    local_today = @tz.utc_to_local(now_utc).to_date
    midnight    = Time.new(local_today.year, local_today.month, local_today.day, 0, 0, 0)
    start_utc   = @tz.local_to_utc(midnight).to_i
    [ start_utc, start_utc + 86_400, local_today ]
  end

  def producer_ids
    @config.plugs.select { |p| p.role == :producer }.map(&:id)
  end

  def consumer_ids
    @config.plugs.select { |p| p.role == :consumer }.map(&:id)
  end

  def energy_delta_wh(plug_ids, start_ts, end_ts)
    return 0.0 if plug_ids.empty?

    sql = EnergyDeltas.cte(filter_plug_ids: true) + <<~SQL
      SELECT plug_id, SUM(delta_wh) AS delta
        FROM deltas
       GROUP BY plug_id
    SQL

    rows = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.sanitize_sql_array([ sql, plug_ids, start_ts, end_ts ])
    )
    rows.sum { |row| row["delta"] || 0 }.to_f
  end

  def today_power_series(start_ts, end_ts)
    PowerSeries.from_samples(
      plugs: @config.plugs,
      start_ts: start_ts,
      end_ts: end_ts,
      bucket_seconds: PowerSeries::SAMPLE_5MIN_BUCKET_SECONDS
    )
  end
end
