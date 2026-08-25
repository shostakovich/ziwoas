module Dashboard
  # The hero pairs the current PV watts with the battery's SoC. Which number
  # the PV half shows — inverter reading or producer-plug fallback — and which
  # battery face fits the state are decided here, on the server, once.
  class HeroComponent < ApplicationComponent
    def initialize(live:, weather_asset:, weather_alt:)
      @live          = live
      @weather_asset = weather_asset
      @weather_alt   = weather_alt
    end

    private

    attr_reader :live, :weather_asset, :weather_alt

    def flow = live.energy_flow

    def pv_watt
      return [ flow.solar_w || 0, 0 ].max.round if flow.solakon_online

      producer = live.plugs.find { |plug| plug.role == :producer }
      (producer.apower_w || 0).abs.round if producer&.online
    end

    def battery? = flow.solakon_online

    def soc = flow.battery_soc_pct || "—"

    def battery_asset
      ApplicationHelper::BATTERY_ASSETS.fetch(flow.battery_state, ApplicationHelper::DEFAULT_BATTERY_ASSET)
    end
  end
end
