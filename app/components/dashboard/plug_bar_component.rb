module Dashboard
  # Colours are keyed by config position, so a plug keeps its colour across renders and charts.
  class PlugBarComponent < ApplicationComponent
    PLUG_COLORS = (1..10).map { |n| "var(--viz-#{n})" }.freeze
    PRODUCER_COLOR = "var(--viz-solar)".freeze

    def self.color_at(position) = PLUG_COLORS[position.to_i % PLUG_COLORS.length]

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

    def color(plug) = self.class.color_at(consumer_order.index(plug.id))

    def consumer_order
      @consumer_order ||= live.plugs.select { |plug| plug.role == :consumer }.map(&:id)
    end
  end
end
