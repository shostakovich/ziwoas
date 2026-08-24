json.plugs @live.plugs.map(&:to_h)
json.energy_flow @live.energy_flow.to_h
json.now_ts @live.now_ts
json.offline_after_s @live.offline_after_s
json.stale_after_s @live.stale_after_s
