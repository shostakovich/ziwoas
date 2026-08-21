module Plugs
  class Measurement
    OFFLINE_AFTER_S = 120

    attr_reader :plug_id, :watt, :last_seen_at

    def self.for(plug_ids, now: Time.current, offline_after_s: OFFLINE_AFTER_S)
      Collection.new(plug_ids: Array(plug_ids), now: now, offline_after_s: offline_after_s)
    end

    def initialize(plug_id:, watt:, last_seen_at:, now:, offline_after_s:)
      @plug_id         = plug_id
      @watt            = watt
      @last_seen_at    = last_seen_at
      @now             = now
      @offline_after_s = offline_after_s
    end

    def offline? = age.nil? || age > @offline_after_s

    def reported_watt = offline? ? nil : watt

    def age
      return nil if last_seen_at.nil?
      @now - last_seen_at
    end

    class Collection
      def initialize(plug_ids:, now:, offline_after_s:)
        @plug_ids        = plug_ids
        @now             = now
        @offline_after_s = offline_after_s
      end

      def [](plug_id) = measurements[plug_id]

      # nil, not 0.0 — a measured zero and a missing measurement must not read the same.
      def total_w(plug_ids = @plug_ids)
        unknown = plug_ids - @plug_ids
        raise ArgumentError, "not measured here: #{unknown.join(", ")}" if unknown.any?

        online = measurements.values_at(*plug_ids).reject(&:offline?)
        return nil if online.empty?
        online.sum(&:watt)
      end

      private

      def measurements
        @measurements ||= begin
          samples = Plugs::Sample.latest_per_plug(@plug_ids).index_by(&:plug_id)
          @plug_ids.index_with do |plug_id|
            sample = samples[plug_id]
            Plugs::Measurement.new(
              plug_id:         plug_id,
              watt:            sample&.apower_w,
              last_seen_at:    sample && Time.zone.at(sample.ts),
              now:             @now,
              offline_after_s: @offline_after_s
            )
          end
        end
      end
    end
  end
end
