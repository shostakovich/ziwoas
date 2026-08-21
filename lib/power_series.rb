class PowerSeries
  module Types
    include Dry.Types()
  end

  class Bucket < Dry::Struct
    attribute :ts,            Types::Coercible::Integer
    attribute :production_w,  Types::Coercible::Float
    attribute :consumption_w, Types::Coercible::Float
  end

  SAMPLE_5MIN_BUCKET_SECONDS = 300
  SECONDS_PER_HOUR           = 3600.0

  class << self
    def from_samples(plugs:, start_ts:, end_ts:, bucket_seconds:)
      roster = PlugRoster.wrap(plugs)
      new(readings: sample_readings(roster, start_ts, end_ts, bucket_seconds),
          plugs: roster,
          bucket_seconds: bucket_seconds)
    end

    def from_5min(rows, plugs:)
      new(readings: rows.map { |row| [ row.plug_id, row.bucket_ts, row.avg_power_w ] },
          plugs: plugs,
          bucket_seconds: SAMPLE_5MIN_BUCKET_SECONDS)
    end

    def bucket_ts_sql(bucket_seconds)
      seconds = Integer(bucket_seconds)
      "(ts / #{seconds}) * #{seconds}"
    end

    private

    def sample_readings(roster, start_ts, end_ts, bucket_seconds)
      plug_ids = roster.ids
      return [] if plug_ids.empty?

      sql = <<~SQL
        SELECT plug_id,
               #{bucket_ts_sql(bucket_seconds)} AS bucket_ts,
               AVG(apower_w) AS avg_power_w
          FROM samples
         WHERE plug_id IN (?) AND ts >= ? AND ts < ?
         GROUP BY plug_id, bucket_ts
      SQL

      ActiveRecord::Base.connection.exec_query(
        ActiveRecord::Base.sanitize_sql_array([ sql, plug_ids, start_ts, end_ts ])
      ).map { |row| [ row["plug_id"], row["bucket_ts"], row["avg_power_w"] ] }
    end
  end

  def initialize(readings:, plugs:, bucket_seconds:)
    @roster         = PlugRoster.wrap(plugs)
    @bucket_seconds = Integer(bucket_seconds)
    @readings       = normalize(readings)
  end

  def each_bucket(&block)
    return to_enum(:each_bucket) unless block_given?

    buckets.each(&block)
    self
  end

  def signed_watts_by_ts(plug_id)
    watts_by_plug.fetch(plug_id, {})
  end

  def self_consumed_wh(produced_wh:, consumed_wh:)
    [ overlap_wh, produced_wh, consumed_wh ].min
  end

  private

  def normalize(readings)
    readings
      .filter_map do |plug_id, bucket_ts, avg_power_w|
        next unless @roster.measured?(plug_id)

        [ plug_id, bucket_ts.to_i, avg_power_w.to_f ]
      end
      .sort_by { |_plug_id, bucket_ts, _watt| bucket_ts }
  end

  def signed(plug_id, watt)
    @roster.signed_watts(plug_id, watt)
  end

  def buckets
    @buckets ||= totals_by_ts.map { |ts, totals| Bucket.new(ts: ts, **totals) }
  end

  def totals_by_ts
    @readings.each_with_object({}) do |(plug_id, ts, watt), totals|
      totals[ts] ||= { production_w: 0.0, consumption_w: 0.0 }
      totals[ts][@roster.bucket_key(plug_id)] += signed(plug_id, watt)
    end
  end

  def watts_by_plug
    @watts_by_plug ||= @readings.each_with_object({}) do |(plug_id, ts, watt), by_plug|
      (by_plug[plug_id] ||= {})[ts] = signed(plug_id, watt)
    end
  end

  def overlap_wh
    bucket_hours = @bucket_seconds / SECONDS_PER_HOUR
    each_bucket.sum { |bucket| [ bucket.production_w, bucket.consumption_w ].min * bucket_hours }
  end
end
