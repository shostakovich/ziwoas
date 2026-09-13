class SolakonController < ApplicationController
  def index
    config = app_config.solakon
    @live = LiveState.for(config: app_config)
    @control_enabled = config&.control_enabled || false
    @runtime_state = Solakon::Control::State.current
    @latest_reading = Solakon::Reading.newest_first.first
    @latest_snapshot = Solakon::Snapshot.latest
    @history_payload = Solakon::History.new(range_key: "24h").payload
    calendar = SunCalendar::Builder.new(
      location: app_config.location,
      producer_ids: Plugs::Roster.wrap(app_config.plugs).producer_ids
    )
    @sun_calendar = calendar.build(calendar.latest_year)
    @shading = Shading::Builder.new(location: app_config.location).build
  end

  def history
    render json: Solakon::History.new(range_key: params[:range].to_s).payload
  end
end
