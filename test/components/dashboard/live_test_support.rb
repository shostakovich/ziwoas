# In-memory LiveState stand-ins for dashboard component tests — the
# components only read plugs and energy_flow, so a Struct suffices and no
# test needs the database.
module Dashboard
  module LiveTestSupport
    FakeLive = Struct.new(:plugs, :energy_flow, keyword_init: true)

    def live(plugs: [], flow: {})
      FakeLive.new(plugs: plugs, energy_flow: energy_flow(**flow))
    end

    def energy_flow(**overrides)
      EnergyFlow.new({
        solakon_online: false, home_w: nil, solakon_ac_w: nil,
        solar_w: nil, battery_soc_pct: nil, battery_w: nil, battery_state: nil,
        grid_w: nil, flows: EnergyFlow::Flows.unknown
      }.merge(overrides))
    end

    def row(id:, role:, online: true, apower_w: 0.0, name: nil, last_seen_ts: nil)
      LiveState::Row.new(
        id: id, name: name || id.capitalize, role: role,
        online: online, apower_w: apower_w, last_seen_ts: last_seen_ts
      )
    end
  end
end
