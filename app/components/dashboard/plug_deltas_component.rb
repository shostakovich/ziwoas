module Dashboard
  # Data carrier for the 24h chart: per-plug bucket deltas the chart appends
  # in place. Chart.js instances live in the client, so they get data, not
  # markup — same reasoning as EnergyFlowStateComponent.
  class PlugDeltasComponent < ApplicationComponent
    def initialize(deltas:)
      @deltas = deltas
    end

    private

    def payload_json = @deltas.to_json
  end
end
