module Solakon
  module Control
    module Tick
      MAX_CONSECUTIVE_FAILURES = 3

      def self.call(reading:, roster:, client:, control:, now:, cache: Rails.cache)
        return Outcome.paused unless control.active?

        load = LoadReader.new(roster: roster, now: now, cache: cache).load_estimate
        decision = Policy.decide(reading: reading, load: load, previous: previous(control, now))

        begin
          client.apply_control!(power_w: decision.target_w, min_soc: Reading::MIN_SOC_PCT)
        rescue Client::Error => e
          return after_write_failure(client, control, e)
        end

        control.store!(decision, at: now)
        control.reset_failures!
        Outcome.applied(decision: decision, load: load, reading: reading)
      end

      def self.previous(control, now)
        stored = control.stored
        return nil if stored.nil? || stored.at <= now - Client::REMOTE_TIMEOUT_S.seconds

        stored.decision
      end

      # Write failures only. The reading is supplied by the caller, so a read failure
      # never reaches this module.
      def self.after_write_failure(client, control, error)
        failures = control.count_failure!
        return Outcome.failed(failures: failures, error: error.message) if failures < MAX_CONSECUTIVE_FAILURES

        begin
          client.release_control!
        rescue Client::Error => e
          return Outcome.failed(failures: failures,
                                error: "#{error.message}; could not relinquish remote control: #{e.message}")
        end

        control.clear!
        control.reset_failures!
        Outcome.released(failures: failures, error: error.message)
      end
    end
  end
end
