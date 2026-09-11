class SolakonController < ApplicationController
  def index
    config = app_config.solakon
    @live = LiveState.for(config: app_config)
    @control_enabled = config&.control_enabled || false
    @runtime_state = Solakon::Control::State.current
    @latest_reading = Solakon::Reading.newest_first.first
    @latest_snapshot = Solakon::Snapshot.latest
    @history_payload = Solakon::History.new(range_key: "24h").payload
  end

  def history
    render json: Solakon::History.new(range_key: params[:range].to_s).payload
  end
end
