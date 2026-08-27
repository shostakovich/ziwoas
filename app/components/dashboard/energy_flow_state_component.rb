module Dashboard
  # Data carrier, not markup: the energy-flow SVG holds running animations that
  # must survive updates, so Turbo replaces only this hidden div and the
  # energy-flow Stimulus controller reads the fresh state from it. It doubles
  # as the heartbeat the live-freshness controller listens for.
  class EnergyFlowStateComponent < ApplicationComponent
    def initialize(live:)
      @flow = live.energy_flow
    end

    private

    def state_json = @flow.to_json
  end
end
