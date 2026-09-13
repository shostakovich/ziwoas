class EnergySummary
  MAX_PLAUSIBLE_W = EnergyDeltas::MAX_PLAUSIBLE_W

  attr_reader :produced, :consumed, :self_consumed, :savings_eur, :date

  def initialize(config:)
    @config     = config
    @zone       = config.location.timezone
    @calculator = SavingsCalculator.new(price_eur_per_kwh: config.electricity_price_eur_per_kwh)
  end

  def compute_today
    start_ts, end_ts, today = today_bounds_utc
    @produced      = Energy.wh(energy_delta_wh(producer_ids, start_ts, end_ts))
    @consumed      = Energy.wh(energy_delta_wh(consumer_ids, start_ts, end_ts))
    @self_consumed = Energy.wh(
      today_power_series(start_ts, end_ts)
        .self_consumed_wh(produced_wh: @produced.wh, consumed_wh: @consumed.wh)
    )
    @savings_eur   = @calculator.savings_eur(@produced)
    @date          = today.to_s
    self
  end

  def autarky_ratio = @self_consumed.ratio_to(@consumed)

  def self_consumption_ratio = @self_consumed.ratio_to(@produced)

  private

  def today_bounds_utc
    midnight = @zone.now.beginning_of_day
    [ midnight.to_i, (midnight + 1.day).to_i, midnight.to_date ]
  end

  def producer_ids = @config.plug_roster.producer_ids

  def consumer_ids = @config.plug_roster.consumer_ids

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
