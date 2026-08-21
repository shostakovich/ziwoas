class PlugMeasurement
  OFFLINE_AFTER         = 5.minutes
  DEFAULT_STALE_AFTER_S = 120

  attr_reader :plug_id, :watt, :last_seen_at

  def self.for(plug_ids, now: Time.current, stale_after_s: DEFAULT_STALE_AFTER_S)
    Collection.new(plug_ids: Array(plug_ids), now: now, stale_after_s: stale_after_s)
  end

  def initialize(plug_id:, watt:, last_seen_at:, now:, stale_after_s:)
    @plug_id       = plug_id
    @watt          = watt
    @last_seen_at  = last_seen_at
    @now           = now
    @stale_after_s = stale_after_s
  end

  def stale? = age.nil? || age > @stale_after_s

  # Slower than stale? on purpose: an idle Fritz plug is polled once a minute,
  # so two missed polls must not read as a dead device.
  def offline? = age.nil? || age > OFFLINE_AFTER

  def age
    return nil if last_seen_at.nil?
    @now - last_seen_at
  end

  class Collection
    def initialize(plug_ids:, now:, stale_after_s:)
      @plug_ids      = plug_ids
      @now           = now
      @stale_after_s = stale_after_s
    end

    def [](plug_id) = measurements[plug_id]

    # nil, not 0.0 — a measured zero and a missing measurement must not read the same.
    def total_w(plug_ids = @plug_ids)
      fresh = measurements.values_at(*plug_ids).compact.reject(&:stale?)
      return nil if fresh.empty?
      fresh.sum(&:watt)
    end

    private

    def measurements
      @measurements ||= begin
        samples = Sample.latest_per_plug(@plug_ids).index_by(&:plug_id)
        @plug_ids.index_with do |plug_id|
          sample = samples[plug_id]
          PlugMeasurement.new(
            plug_id:       plug_id,
            watt:          sample&.apower_w,
            last_seen_at:  sample && Time.zone.at(sample.ts),
            now:           @now,
            stale_after_s: @stale_after_s
          )
        end
      end
    end
  end
end
