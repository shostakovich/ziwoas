module Solakon
  # The four panels over the day, one line each with its own colour and its
  # name written next to it, so the one that falls back in the morning can be
  # told from the one that falls back in the evening.
  class PanelCurvesComponent < ApplicationComponent
    WIDTH = 720
    HEIGHT = 220
    LEFT = 36
    # Room at the right edge for the last hour's label, which is centred on
    # the tick sitting on the plot's edge.
    RIGHT = 24
    TOP = 12
    BOTTOM = 22
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
    # How far the lowest name stays clear of the axis.
    LABEL_MARGIN = 4

    Series = Data.define(:key, :label, :segments)
    Hit = Data.define(:x, :width, :title)
    Label = Data.define(:x, :y, :text, :key)

    def initialize(panels:)
      @panels = panels
    end

    def empty? = @panels.empty?

    def view_box = "0 0 #{WIDTH} #{HEIGHT}"

    def plot_top = TOP

    def plot_height = HEIGHT - TOP - BOTTOM

    def plot_left = LEFT

    def plot_right = WIDTH - RIGHT

    def baseline_y = number(y(0))

    def series
      curves.map { |curve| Series.new(key: curve.key, label: name(curve.key), segments: segments(curve)) }
    end

    # The names sit at the same hour, pushed apart where two lines run close
    # together and lifted back over the axis where that pushed the last one
    # off the plot.
    def labels
      placed = spread(curves.filter_map { |curve| starting_label(curve) }.sort_by(&:y))
      overflow = placed.map(&:y).max.to_f - (y(0) - LABEL_MARGIN)
      return placed if placed.empty? || overflow <= 0

      placed.map { |label| label.with(y: number(label.y - overflow)) }
    end

    def grid
      grid_step.step(max_w - 1, grid_step).map do |watts|
        Label.new(x: LEFT - 5, y: number(y(watts)), text: watts.to_s, key: nil)
      end
    end

    def hour_labels(density)
      step = density == :sparse ? SPARSE_HOUR_STEP : DENSE_HOUR_STEP

      hours.first.step(hours.last, step).map do |hour|
        Label.new(x: number(x(hour)), y: HEIGHT - 6, text: density == :sparse ? hour.to_s : "#{hour} Uhr", key: nil)
      end
    end

    def hits
      values = curves.to_h { |curve| [ curve.key, curve.points.to_h ] }

      hours.map do |hour|
        width = [ x(hour + 1), plot_right ].min - x(hour)
        Hit.new(x: number(x(hour)), width: number(width), title: title_for(hour, values))
      end
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

    def curves = @panels.curves

    def name(key) = "Panel #{key.to_s.delete_prefix('pv')}"

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
      Label.new(x: number(x(hour) + LABEL_OFFSET), y: number(y(watts)), text: name(curve.key), key: curve.key)
    end

    # The middle of the day where it was measured, otherwise the hour closest
    # to it.
    def label_hour(curve)
      curve.points.map(&:first).min_by { |hour| (hour - LABEL_HOUR).abs }
    end

    def segments(curve)
      curve.points
           .slice_when { |(previous, _), (hour, _)| hour - previous > 1 }
           .map { |run| run.map { |hour, watts| "#{number(x(hour))},#{number(y(watts))}" }.join(" ") }
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
      @max_w ||= [ (@panels.max.to_f / GRID_STEP_W).ceil * GRID_STEP_W, GRID_STEP_W ].max
    end

    def grid_step = (max_w / MAX_GRID_LINES.to_f / GRID_STEP_W).ceil * GRID_STEP_W

    def span = [ hours.last - hours.first, 1 ].max

    def x(hour) = LEFT + (hour - hours.first) / span.to_f * (WIDTH - LEFT - RIGHT)

    # to_f: the grid's watts are whole numbers, and integer division
    # would put every line on the axis.
    def y(watts) = TOP + (1 - watts.to_f / max_w) * (HEIGHT - TOP - BOTTOM)
  end
end
