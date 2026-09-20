class ReportsController < ApplicationController
  def index
    @report = EnergyReport.new(
      params: report_params,
      plugs: app_config.plugs,
      location: app_config.location
    ).build
  end

  private

  def report_params
    params.permit(:preset, :start_date, :end_date, :selected_date)
  end
end
