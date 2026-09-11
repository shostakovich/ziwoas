module Solakon
  module Control
    # One control tick: decide a target from the reading the monitor just took
    # and write it to the inverter. The target is written every tick — the power
    # register is volatile, writes are cheap, and each write re-arms the
    # inverter's 150s remote-control watchdog, so no separate heartbeat or
    # write-deadband logic is needed.
    #
    # Configuration gates stay with the caller; what stays here is everything
    # that depends on the loop's own runtime state.
    module Tick
      MAX_CONSECUTIVE_FAILURES = 3

      def self.call(reading:, roster:, client:, control:, now:, cache: Rails.cache)
        return Outcome.paused unless control.auto_regulation_active?

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

      # A stored decision only describes the inverter while the inverter is still
      # holding it. Past the remote-control watchdog the device has fallen back
      # on its own, so the next tick starts from nothing.
      def self.previous(control, now)
        stored = control.stored
        return nil if stored.nil? || stored.at <= now - Client::REMOTE_TIMEOUT_S.seconds

        stored.decision
      end

      # Reached for *write* failures; the reading is supplied by the caller, so
      # read failures abort upstream where the inverter's own watchdog is the
      # backstop. After repeated write failures we release remote control so the
      # inverter reverts to its default behaviour. The failed decision is NOT
      # stored — the trim loop must integrate against targets the inverter
      # actually received.
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
