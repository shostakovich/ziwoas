module Dashboard
  # The stacked consumption bar with its legend. Colors are keyed by the
  # plug's position in the config, so a plug keeps its color across renders
  # and across clients — the old JS assigned first-seen order per tab instead.
  class PlugBarComponent < ApplicationComponent
    PLUG_COLORS = %w[
      #3b82f6 #10b981 #8b5cf6 #ef4444 #06b6d4
      #ec4899 #84cc16 #6366f1 #14b8a6 #f43f5e
    ].freeze
    PRODUCER_COLOR = "#f59f00".freeze

    def initialize(live:)
      @live = live
    end

    private

    attr_reader :live

    def consumers
      @consumers ||= live.plugs
        .select { |plug| plug.role == :consumer && plug.online && plug.apower_w.to_f > 0 }
        .sort_by { |plug| -plug.apower_w }
    end

    def producers
      @producers ||= live.plugs.select { |plug| plug.role == :producer && plug.online }
    end

    def total_w = @total_w ||= consumers.sum(&:apower_w)

    def width_pct(plug) = (plug.apower_w / total_w) * 100

    def color(plug)
      index = consumer_order.index(plug.id) || 0
      PLUG_COLORS[index % PLUG_COLORS.length]
    end

    def consumer_order
      @consumer_order ||= live.plugs.select { |plug| plug.role == :consumer }.map(&:id)
    end
  end
end
