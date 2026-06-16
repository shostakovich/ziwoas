require "config_loader"
require "solakon_client"

class ZeroExportTickJob < ApplicationJob
  queue_as :default

  FLOOR_CACHE_KEY = "zero_export.floor_w".freeze

  def perform(client: nil, reader_now: Time.now)
    config  = ConfigLoader.app_config
    solakon = config.solakon
    return Rails.logger.info("zero_export: not configured") if solakon.nil?
    return Rails.logger.info("zero_export: disabled")       unless solakon.enabled

    reader = ConsumptionReader.new(plugs: config.plugs, now: reader_now,
                                   stale_after_s: solakon.stale_after_s)
    floor       = Rails.cache.fetch(FLOOR_CACHE_KEY, expires_in: 1.hour) { reader.guaranteed_floor_w }
    consumption = reader.current_consumption_w
    target      = ZeroExportController.target_output_w(consumption_w: consumption, floor_w: floor)

    client ||= SolakonClient.new(host: solakon.host, port: solakon.port, unit_id: solakon.unit_id)

    begin
      client.ensure_remote_control!
      client.ensure_minimum_soc!(ZeroExportController::MIN_SOC_PCT)
      client.write_output_power!(target)
      state = client.read_state
      Rails.logger.info(
        "zero_export: consumption=#{consumption.round}W floor=#{floor.round}W target=#{target}W " \
        "soc=#{state.battery_soc}% active=#{state.active_power_w}W " \
        "pv=#{state.pv_power_w}W battery=#{state.battery_power_w}W"
      )
    rescue SolakonClient::Error => e
      Rails.logger.warn("zero_export: Modbus failure (target was #{target}W): #{e.message}")
    end
  end
end
