require "config_loader"
require "solakon_client"

# One control tick: decide a target from the state the monitor just read and
# write it to the inverter. Runs synchronously from SolakonMonitorJob every
# 30s. The target is written every tick — the power register is volatile,
# writes are cheap, and each write re-arms the inverter's 150s remote-control
# watchdog, so no separate heartbeat or write-deadband logic is needed.
class ZeroExportTickJob < ApplicationJob
  queue_as :default

  MAX_CONSECUTIVE_FAILURES = 3

  def perform(client:, state:, reader_now: Time.current)
    config  = ConfigLoader.app_config
    solakon = config.solakon
    return Rails.logger.info("zero_export: not configured") if solakon.nil?
    return Rails.logger.info("zero_export: control disabled") unless solakon.control_enabled

    control = SolakonControlState.current
    return Rails.logger.info("zero_export: runtime paused") unless control.auto_regulation_active?

    reader  = ConsumptionReader.new(plugs: config.plugs, now: reader_now, stale_after_s: solakon.stale_after_s)
    load    = reader.load_estimate
    reading = SolakonReading.from_state(state, taken_at: reader_now)

    decision = ZeroExportController.decide(reading: reading, load: load, previous: control.last_decision)

    begin
      client.apply_control!(power_w: decision.target_w, min_soc: SolakonReading::MIN_SOC_PCT)
    rescue SolakonClient::Error => e
      return handle_failure(client, e, control)
    end

    control.remember_decision!(decision)
    control.reset_failures!
    log(decision, load, reading)
  end

  private

  def log(decision, load, reading)
    current = load.current_w.nil? ? "stale" : "#{load.current_w.round}W"
    Rails.logger.info(
      "zero_export: state=#{decision.state} target=#{decision.target_w}W load=#{current} " \
      "floor=#{load.floor_w.round}W " \
      "soc=#{reading.battery_soc_pct}% temp=#{reading.battery_temperature_c}C pv=#{reading.pv_power_w}W"
    )
  end

  # Reached for *write* failures (the live state is supplied by the monitor, so
  # read failures abort upstream in SolakonMonitorJob, where the inverter's 150s
  # hardware watchdog is the backstop). After repeated write failures we release
  # remote control so the inverter reverts to its own default behavior. The
  # failed decision is NOT remembered — the trim loop must integrate against
  # targets the inverter actually received.
  def handle_failure(client, error, control)
    failures = control.register_failure!
    Rails.logger.warn("zero_export: Modbus failure #{failures}/#{MAX_CONSECUTIVE_FAILURES}: #{error.message}")
    return if failures < MAX_CONSECUTIVE_FAILURES

    begin
      client.release_control!
      control.reset_failures!
      Rails.logger.warn("zero_export: relinquished remote control after #{failures} consecutive failures")
    rescue SolakonClient::Error => e
      Rails.logger.warn("zero_export: failed to relinquish remote control: #{e.message}")
    end
  end
end
