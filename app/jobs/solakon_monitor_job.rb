require "config_loader"
require "solakon_client"

class SolakonMonitorJob < ApplicationJob
  queue_as :default

  def perform(client: nil, now: Time.current)
    config = ConfigLoader.app_config
    solakon = config.solakon

    return Rails.logger.info("solakon_monitor: not configured") if solakon.nil?
    return Rails.logger.info("solakon_monitor: disabled") unless solakon.monitoring_enabled

    client ||= SolakonClient.from_config(solakon)
    state = client.read_state

    SolakonReading.from_state(state, taken_at: now).save!

    ZeroExportTickJob.perform_now(client: client, state: state, reader_now: now) if solakon.control_enabled
    broadcast_dashboard_refresh
  rescue SolakonClient::Error => e
    # A read failure aborts here, so control never runs and no setpoint is
    # written. With no write to re-arm REG_REMOTE_TIMEOUT, the inverter's own
    # 150s remote-control watchdog drops remote control autonomously — that
    # hardware watchdog is the intended backstop for read outages. The tick
    # job's consecutive-failure release_control! covers *write* failures.
    Rails.logger.warn("solakon_monitor: Modbus failure: #{e.message}")
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("solakon_monitor: invalid reading: #{e.record.errors.full_messages.join(", ")}")
  end

  private

  def broadcast_dashboard_refresh
    ActionCable.server.broadcast("dashboard", { solakon: true })
  rescue StandardError => e
    Rails.logger.warn("solakon_monitor: dashboard broadcast failed: #{e.message}")
  end
end
