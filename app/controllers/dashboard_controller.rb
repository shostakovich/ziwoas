class DashboardController < ApplicationController
  def index
    @live = LiveState.for(config: app_config)
    @summary = EnergySummary.new(config: app_config).compute_today
    @weather_asset, @weather_alt = WeatherRecord.dashboard_icon
  end
end
