module Solakon
  # The four panels over the day, each line named next to itself, so the one
  # that falls back in the morning can be told from the one in the evening.
  class PanelCurvesComponent < ApplicationComponent
    WIDTH = 720
    HEIGHT = 220
    MARGINS = {
      top: 12,
      # Room at the right edge for the last hour's label, which is centred on
      # the tick sitting on the plot's edge.
      right: 24,
      bottom: 22,
      left: 36
    }.freeze
    GRID_STEP_W = 100
    MAX_GRID_LINES = 4
    DENSE_HOUR_STEP = 2
    SPARSE_HOUR_STEP = 4
    # Where the names are written: the middle of the day, where the lines are
    # furthest from the axis.
    LABEL_HOUR = 13
    # At least the phone's enlarged line height, so two names never sit on top
    # of each other where the lines run together.
    LABEL_GAP = 20
    LABEL_OFFSET = 6
    LABEL_MARGIN = 4
    VALUE_LABEL_GAP = 5
    VALUE_LABEL_DROP = 3.5
    HOUR_LABEL_Y = HEIGHT - 6

    Series = Data.define(:key, :label, :segments)
    Hit = Data.define(:rect, :title)
    Label = Data.define(:x, :y, :text, :key)

    def initialize(panels:)
      @panels = panels
    end

    def empty? = @panels.empty?

    def plot
      @plot ||= Plot.new(width: WIDTH, height: HEIGHT, margins: MARGINS, x: hours, y: 0..max_w)
    end

    def series
      curves.map { |curve| Series.new(key: curve.key, label: name(curve.key), segments: plot.polylines(curve.points)) }
    end

    def labels
      placed = spread(curves.filter_map { |curve| starting_label(curve) }.sort_by(&:y))
      overflow = placed.map(&:y).max.to_f - (plot.bottom - LABEL_MARGIN)
      return placed if placed.empty? || overflow <= 0

      placed.map { |label| label.with(y: number(label.y - overflow)) }
    end

    def grid_lines = grid.map(&:at)

    def value_labels
      grid.map do |tick|
        Label.new(x: plot.left - VALUE_LABEL_GAP, y: number(tick.at + VALUE_LABEL_DROP), text: tick.value.to_s, key: nil)
      end
    end

    def hour_labels(density)
      step = density == :sparse ? SPARSE_HOUR_STEP : DENSE_HOUR_STEP

      plot.x_ticks(hours.step(step)).map do |tick|
        text = density == :sparse ? tick.value.to_s : "#{tick.value} Uhr"
        Label.new(x: tick.at, y: HOUR_LABEL_Y, text: text, key: nil)
      end
    end

    def hits
      values = curves.to_h { |curve| [ curve.key, curve.points.to_h ] }

      hours.zip(plot.columns(hours)).map { |hour, column| Hit.new(rect: column, title: title_for(hour, values)) }
    end

    def period
      return nil if @panels.since.nil?

      "seit #{@panels.since.strftime('%d.%m.%Y')} · #{@panels.days} #{@panels.days == 1 ? 'Tag' : 'Tage'}"
    end

    def note
      "Gezählt sind nur Tage, an denen alle vier Panels geliefert haben — ein Panel, das noch nicht " \
        "angeschlossen war, meldet null Watt und würde seine eigene Linie nach unten ziehen."
    end

    private

    delegate :y, :number, to: :plot, private: true

    def curves = @panels.curves

    def name(key) = "Panel #{key.to_s.delete_prefix('pv')}"

    def grid = plot.y_ticks(grid_step.step(max_w - 1, grid_step))

    def spread(labels)
      labels.each_with_object([]) do |label, placed|
        previous = placed.last
        too_close = previous && label.y - previous.y < LABEL_GAP
        placed << (too_close ? label.with(y: number(previous.y + LABEL_GAP)) : label)
      end
    end

    def starting_label(curve)
      return nil if curve.empty?

      hour = label_hour(curve)
      watts = curve.points.to_h.fetch(hour)
      Label.new(x: number(plot.x(hour) + LABEL_OFFSET), y: number(y(watts)), text: name(curve.key), key: curve.key)
    end

    def label_hour(curve)
      curve.points.map(&:first).min_by { |hour| (hour - LABEL_HOUR).abs }
    end

    def title_for(hour, values)
      [
        "#{hour}–#{hour + 1} Uhr",
        *curves.map { |curve| "#{name(curve.key)} #{watts(values.fetch(curve.key)[hour])}" }
      ].join(" · ")
    end

    def watts(value) = value.nil? ? "keine Daten" : "Ø #{value.round} W"

    def hours
      @hours ||= begin
        all = @panels.hours
        all.empty? ? (0..0) : (all.min..all.max)
      end
    end

    def max_w
      @max_w ||= [ Plot.round_up(@panels.max.to_f, to: GRID_STEP_W), GRID_STEP_W ].max
    end

    def grid_step = Plot.round_up(max_w / MAX_GRID_LINES.to_f, to: GRID_STEP_W)
  end
end
