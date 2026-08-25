# Renders the dashboard's live regions server-side and pushes them to every
# open page over Turbo Streams — the pattern WeatherBroadcaster established.
# Two cadences: broadcast_live rides the collector's 5s Shelly rhythm (and the
# 30s Solakon monitor), broadcast_summary recomputes the day's totals once a
# minute. The live beat doubles as the client's heartbeat: it also fires when
# nothing changed, so a silent page can tell a dead link from a quiet house.
module DashboardBroadcaster
  STREAM = "dashboard_live".freeze

  module_function

  def broadcast_live(config: ConfigLoader.app_config, deltas: [])
    live = LiveState.for(config: config)
    weather_asset, weather_alt = WeatherRecord.dashboard_icon

    replace Dashboard::HeroComponent.new(live: live, weather_asset: weather_asset, weather_alt: weather_alt),
            target: "dashboard_hero"
    Dashboard::TileComponent.live_tiles(live).each { |tile| replace tile, target: tile.id }
    replace Dashboard::PlugBarComponent.new(live: live), target: "dashboard_plug_bar"
    replace Dashboard::EnergyFlowStateComponent.new(live: live), target: "energy_flow_state"
    replace Dashboard::PlugDeltasComponent.new(deltas: deltas), target: "plug_deltas" if deltas.any?
    broadcast_switch_heads(config)
  end

  def broadcast_summary(config: ConfigLoader.app_config)
    summary = EnergySummary.new(config: config).compute_today
    Dashboard::TileComponent.summary_tiles(summary).each { |tile| replace tile, target: tile.id }
  end

  def broadcast_switch_heads(config)
    switchable = config.plugs.select(&:switchable)
    return if switchable.empty?

    Switching::Row.build_all(switchable).each do |row|
      Turbo::StreamsChannel.broadcast_replace_to(
        STREAM,
        target: "sw_head_#{row.plug.id}",
        partial: "switches/head", locals: { row: row }
      )
    end
  end

  # The channel-level broadcast does not apply Broadcastable's rendering
  # defaults, so without layout: false every fragment would ship the full page.
  def replace(renderable, target:)
    Turbo::StreamsChannel.broadcast_replace_to(
      STREAM, target: target, renderable: renderable, layout: false
    )
  end
end
