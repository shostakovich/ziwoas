module Solakon
  class MonitorJob < ApplicationJob
    queue_as :default

    def perform(client: nil, now: Time.current)
      config = ConfigLoader.app_config
      solakon = config.solakon

      return Rails.logger.info("solakon_monitor: not configured") if solakon.nil?
      return Rails.logger.info("solakon_monitor: disabled") unless solakon.monitoring_enabled

      client ||= Client.from_config(solakon)
      reading = Reading.from_state(client.read_state, taken_at: now)
      reading.save!

      run_control(reading, config, client, now) if solakon.control_enabled
      broadcast_dashboard_refresh
    rescue Client::Error => e
      # Nothing is released here on purpose: without a write to re-arm
      # REG_REMOTE_TIMEOUT the inverter drops remote control by itself.
      Rails.logger.warn("solakon_monitor: Modbus failure: #{e.message}")
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("solakon_monitor: invalid reading: #{e.record.errors.full_messages.join(", ")}")
    end

    private

    def run_control(reading, config, client, now)
      outcome = Control::Tick.call(reading: reading, roster: config.plug_roster, client: client,
                                   control: Control::State.current, now: now)
      Rails.logger.public_send(outcome.log_level, "solakon_control: #{outcome.log_line}")
    end

    def broadcast_dashboard_refresh
      DashboardBroadcaster.broadcast_live
    rescue StandardError => e
      Rails.logger.warn("solakon_monitor: dashboard broadcast failed: #{e.message}")
    end
  end
end
