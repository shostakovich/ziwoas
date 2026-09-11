module Solakon
  module Control
    # One control tick: decide a target from the state the monitor just read and
    # write it to the inverter. Runs synchronously from Solakon::MonitorJob every
    # 30s. The target is written every tick — the power register is volatile,
    # writes are cheap, and each write re-arms the inverter's 150s remote-control
    # watchdog, so no separate heartbeat or write-deadband logic is needed.
    class TickJob < ApplicationJob
      queue_as :default

      MAX_CONSECUTIVE_FAILURES = 3

      def perform(client:, state:, reader_now: Time.current)
        config  = ConfigLoader.app_config
        solakon = config.solakon
        return Rails.logger.info("solakon_control: not configured") if solakon.nil?
        return Rails.logger.info("solakon_control: control disabled") unless solakon.control_enabled

        control = Solakon::Control::State.current
        return Rails.logger.info("solakon_control: runtime paused") unless control.auto_regulation_active?

        reader  = Solakon::Control::LoadReader.new(plugs: config.plugs, now: reader_now)
        load    = reader.load_estimate
        reading = Solakon::Reading.from_state(state, taken_at: reader_now)

        decision = Solakon::Control::Policy.decide(
          reading: reading,
          load: load,
          previous: control.last_decision(at: reader_now)
        )

        begin
          client.apply_control!(power_w: decision.target_w, min_soc: Solakon::Reading::MIN_SOC_PCT)
        rescue Solakon::Client::Error => e
          return handle_failure(client, e, control)
        end

        control.remember_decision!(decision, at: reader_now)
        control.reset_failures!
        log(decision, load, reading)
      end

      private

      def log(decision, load, reading)
        current = load.current_w.nil? ? "stale" : "#{load.current_w.round}W"
        Rails.logger.info(
          "solakon_control: state=#{decision.state} target=#{decision.target_w}W load=#{current} " \
          "floor=#{load.floor_w.round}W " \
          "soc=#{reading.battery_soc_pct}% temp=#{reading.battery_temperature_c}C " \
          "pv=#{reading.pv_power_w}W battery=#{reading.battery_power_w}W"
        )
      end

      # Reached for *write* failures (the live state is supplied by the monitor, so
      # read failures abort upstream in Solakon::MonitorJob, where the inverter's 150s
      # hardware watchdog is the backstop). After repeated write failures we release
      # remote control so the inverter reverts to its own default behavior. The
      # failed decision is NOT remembered — the trim loop must integrate against
      # targets the inverter actually received.
      def handle_failure(client, error, control)
        failures = control.register_failure!
        Rails.logger.warn("solakon_control: Modbus failure #{failures}/#{MAX_CONSECUTIVE_FAILURES}: #{error.message}")
        return if failures < MAX_CONSECUTIVE_FAILURES

        begin
          client.release_control!
          control.reset_decision!
          control.reset_failures!
          Rails.logger.warn("solakon_control: relinquished remote control after #{failures} consecutive failures")
        rescue Solakon::Client::Error => e
          Rails.logger.warn("solakon_control: failed to relinquish remote control: #{e.message}")
        end
      end
    end
  end
end
