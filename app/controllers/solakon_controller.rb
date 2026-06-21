class SolakonController < ApplicationController
  def index
    config = app_config.solakon
    @control_enabled = config&.control_enabled || false
    @runtime_state = SolakonControlState.current
    @latest_reading = SolakonReading.newest_first.first
    @latest_snapshot = SolakonSnapshot.latest
    @history_payload = SolakonHistory.new(range_key: "24h").payload
  end

  def history
    render json: SolakonHistory.new(range_key: params[:range].to_s).payload
  end
end
