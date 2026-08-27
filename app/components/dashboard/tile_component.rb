module Dashboard
  # One dashboard tile. The class methods are the catalog: each names a tile,
  # its DOM id — which doubles as the broadcast target — and how its value is
  # formatted, so the index view and DashboardBroadcaster can never disagree
  # about the markup they produce.
  class TileComponent < ApplicationComponent
    def initialize(id:, label:, value:)
      @id    = id
      @label = label
      @value = value
    end

    attr_reader :id, :label, :value

    class << self
      def produced(summary)
        new(id: "tile_produced", label: "Erzeugt heute", value: kwh(summary.produced.wh))
      end

      def consumed(summary)
        new(id: "tile_consumed", label: "Verbraucht heute", value: kwh(summary.consumed.wh))
      end

      def savings(summary)
        new(id: "tile_savings", label: "Gespart heute", value: "#{de(summary.savings_eur)} €")
      end

      def net_today(summary)
        net = (summary.produced.wh - summary.consumed.wh) / 1000.0
        new(id: "tile_net_today", label: "Bilanz heute", value: "#{'+' if net >= 0}#{de(net)} kWh")
      end

      def autarky(summary)
        new(id: "tile_autarky", label: "Autarkie heute", value: pct(summary.autarky_ratio))
      end

      def self_consumption(summary)
        new(id: "tile_self_consumption", label: "Eigenverbrauch", value: pct(summary.self_consumption_ratio))
      end

      def summary_tiles(summary)
        [ produced(summary), consumed(summary), savings(summary),
          net_today(summary), autarky(summary), self_consumption(summary) ]
      end

      def consumption_now(live)
        flow = live.energy_flow
        any_online = flow.solakon_online || live.plugs.any?(&:online)
        value = any_online && flow.home_w ? "#{flow.home_w.round} W" : "—"
        new(id: "tile_consumption_now", label: "Verbrauch jetzt", value: value)
      end

      def netbalance_now(live)
        grid_w = live.energy_flow.grid_w
        value = grid_w.nil? ? "—" : "#{grid_w <= 0 ? '+' : '−'}#{grid_w.abs.round} W"
        new(id: "tile_netbalance_now", label: "Bilanz jetzt", value: value)
      end

      def live_tiles(live)
        [ consumption_now(live), netbalance_now(live) ]
      end

      def kwh(wh) = "#{de(wh / 1000.0)} kWh"

      def pct(ratio) = "#{de((ratio || 0) * 100, precision: 1)} %"

      def de(number, precision: 2)
        ActiveSupport::NumberHelper.number_to_rounded(
          number, precision: precision, separator: ",", delimiter: "."
        )
      end
    end
  end
end
