module Dashboard
  # The class methods are the dashboard catalog, shared with DashboardBroadcaster so ids and markup match.
  class TileComponent < ApplicationComponent
    def initialize(label:, number:, unit: nil, caption: nil, id: nil)
      @id      = id
      @label   = label
      @number  = number
      @unit    = unit
      @caption = caption
    end

    attr_reader :id, :label, :number, :unit, :caption

    class << self
      def produced(summary)
        energy(id: "tile_produced", label: "Erzeugt heute", kwh: summary.produced.kwh)
      end

      def consumed(summary)
        energy(id: "tile_consumed", label: "Verbraucht heute", kwh: summary.consumed.kwh)
      end

      # No price on record means the savings are unknown, not zero.
      def savings(summary)
        money(id: "tile_savings", label: "Gespart heute", eur: summary.savings_eur)
      end

      def net_today(summary)
        net = (summary.produced.wh - summary.consumed.wh) / 1000.0
        energy(id: "tile_net_today", label: "Bilanz heute", kwh: net, signed: true)
      end

      def autarky(summary)
        share(id: "tile_autarky", label: "Autarkie heute", ratio: summary.autarky_ratio)
      end

      def self_consumption(summary)
        share(id: "tile_self_consumption", label: "Eigen­verbrauchs­quote", ratio: summary.self_consumption_ratio)
      end

      def summary_tiles(summary)
        [ produced(summary), consumed(summary), savings(summary),
          net_today(summary), autarky(summary), self_consumption(summary) ]
      end

      def consumption_now(live)
        flow = live.energy_flow
        any_online = flow.solakon_online || live.plugs.any?(&:online)
        power(id: "tile_consumption_now", label: "Verbrauch jetzt", watts: (flow.home_w if any_online))
      end

      def netbalance_now(live)
        grid_w = live.energy_flow.grid_w
        power(id: "tile_netbalance_now", label: "Bilanz jetzt", watts: grid_w && -grid_w, signed: true)
      end

      def live_tiles(live)
        [ consumption_now(live), netbalance_now(live) ]
      end

      def energy(label:, kwh:, id: nil, signed: false)
        measure(id:, label:, value: kwh, unit: "kWh", precision: 2, signed:)
      end

      def money(label:, eur:, id: nil)
        measure(id:, label:, value: eur, unit: "€", precision: 2)
      end

      def share(label:, ratio:, id: nil)
        measure(id:, label:, value: (ratio || 0) * 100, unit: "%", precision: 1)
      end

      def power(label:, watts:, id: nil, signed: false)
        measure(id:, label:, value: watts, unit: "W", precision: 0, signed:)
      end

      private

      def measure(id:, label:, value:, unit:, precision:, signed: false)
        return new(id:, label:, number: GermanNumber::MISSING) if value.nil?

        number = GermanNumber.format(value, precision:)
        new(id:, label:, number: signed && !value.negative? ? "+#{number}" : number, unit:)
      end
    end
  end
end
