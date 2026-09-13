require "aggregator"
require "config_loader"

class AggregatorJob < ApplicationJob
  queue_as :default

  def perform(today: Date.current, backup_dir: Rails.root.join("storage", "backup").to_s)
    config = ConfigLoader.app_config
    zone = config.location.timezone
    aggregator = Aggregator.new(timezone: zone, plugs: config.plugs)

    Rails.logger.info("aggregator: starting scheduled run")
    aggregator.run_once(today: today)
    aggregator.backup!(backup_dir)
    Solakon::PvHourAggregator.new(timezone: zone).run_once(today: today)
    Rails.logger.info("aggregator: done")
  end
end
