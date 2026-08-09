require "config_loader"

class ScheduleTickJob < ApplicationJob
  queue_as :default

  # A missed edge is replayed at most this far back; anything older lapses,
  # because switching a running appliance off hours late is worse than not
  # switching it at all (ADR-0001). The lower bound also makes a nil watermark
  # indistinguishable from a restart, so the first run needs no special case.
  GRACE = 10.minutes

  def perform
    config = load_config
    now    = Time.current

    plugs         = config.plugs.select(&:switchable)
    rules_by_plug = SwitchRule.enabled.where(plug_id: plugs.map(&:id)).group_by(&:plug_id)

    plugs.each do |plug|
      edge = due_edge(plug.id, rules_by_plug.fetch(plug.id, []), now)
      next if edge && !dispatch(plug, edge, config.mqtt)

      # Every plug of this tick advances, not just the ones that had an edge —
      # otherwise an untouched plug would drag an ancient watermark along.
      SchedulerState.advance!(plug.id, now)
    end
  end

  private

  # The calculator knows neither clock nor grace window: both live here, in the
  # interval we hand it.
  def due_edge(plug_id, rules, now)
    from = [ SchedulerState.last_tick_at(plug_id), now - GRACE ].compact.max
    edge = SwitchEdgeCalculator.new(rules: rules).latest_edge_per_plug(from, now).first
    return nil if edge.nil? || SwitchCommand.manual_after?(plug_id, edge.at)
    edge
  end

  # True once the command is out. On failure this plug's watermark stays put,
  # so the next tick retries it alone while the others move on.
  def dispatch(plug, edge, mqtt_config)
    PlugCommander.switch(plug, edge.action, source: :schedule, mqtt_config: mqtt_config)
    true
  rescue PlugCommander::Error => e
    Rails.logger.warn("ScheduleTick: #{plug.id} rule #{edge.rule_id} #{edge.action} failed: #{e.message}")
    false
  end

  def load_config
    ConfigLoader.app_config
  end
end
