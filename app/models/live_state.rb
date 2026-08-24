class LiveState
  module Types
    include Dry.Types()

    Watt   = Dry::Types["coercible.float"].optional
    Epoch  = Dry::Types["coercible.integer"].optional
    Output = Dry::Types["strict.bool"].optional
  end

  class Row < Dry::Struct
    attribute :id,           Types::Strict::String
    attribute :name,         Types::Strict::String
    attribute :role,         Types::Strict::Symbol
    attribute :online,       Types::Strict::Bool
    attribute :apower_w,     Types::Watt
    attribute :last_seen_ts, Types::Epoch

    def self.build(plug, measurement)
      new(
        id:           plug.id,
        name:         plug.name,
        role:         plug.role,
        online:       !measurement.offline?,
        apower_w:     measurement.reported_watt,
        last_seen_ts: measurement.last_seen_at&.to_i
      )
    end
  end

  class Update < Dry::Struct
    attribute :id,           Types::Strict::String
    attribute :name,         Types::Strict::String
    attribute :role,         Types::Strict::Symbol
    attribute :apower_w,     Types::Watt
    attribute :last_seen_ts, Types::Epoch
    attribute :bucket_ts,    Types::Epoch
    attribute :avg_power_w,  Types::Watt
    attribute :output,       Types::Output
  end

  def self.for(config:, now: Time.current,
               offline_after_s: Plugs::Measurement::OFFLINE_AFTER_S,
               stale_after_s: SolakonReading::STALE_AFTER_S)
    new(config: config, now: now,
        offline_after_s: offline_after_s, stale_after_s: stale_after_s)
  end

  def initialize(config:, now:, offline_after_s:, stale_after_s:)
    @config          = config
    @now             = Time.zone.at(now.to_i)
    @offline_after_s = offline_after_s
    @stale_after_s   = stale_after_s
  end

  def now_ts = @now.to_i

  attr_reader :offline_after_s, :stale_after_s

  def plugs
    @plugs ||= roster.all.map { |plug| Row.build(plug, measurements[plug.id]) }
  end

  def energy_flow
    @energy_flow ||= EnergyFlow.build(home_w: measurements.total_w(roster.consumer_ids),
                                      reading: reading)
  end

  private

  def roster = @roster ||= @config.plug_roster
  def monitored? = @config.solakon&.monitoring_enabled

  def measurements
    @measurements ||=
      Plugs::Measurement.for(roster.ids, now: @now, offline_after_s: @offline_after_s)
  end

  def reading
    SolakonReading.latest_fresh(stale_after_s: @stale_after_s, now: @now) if monitored?
  end
end
