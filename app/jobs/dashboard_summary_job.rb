require "config_loader"

class DashboardSummaryJob < ApplicationJob
  queue_as :default

  def perform
    DashboardBroadcaster.broadcast_summary
  rescue ConfigLoader::Error => e
    Rails.logger.warn("dashboard_summary: config unavailable: #{e.message}")
  end
end
