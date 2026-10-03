module Solakon
  class PanelCurvesComponent
    # One drawing of the four panels inside a frame. The wide frame names each
    # line at its right end, in the margin, with a short leader where the names
    # had to move apart; the narrow one leaves the names to the legend, because
    # on a phone they would sit on top of each other.
    class Chart
      Frame = Data.define(:key, :width, :height, :margins, :hour_step, :named)

      # At least the names' line height at their largest, so two never overlap.
      LABEL_GAP = 20
      # Names start this far right of the plot; their leaders stop short of them.
      LABEL_OFFSET = 12
      LEADER_GAP = 3
      # Half the names' line height at their largest: centred names stay clear of the hours.
      LABEL_MARGIN = 10
      VALUE_LABEL_GAP = 5
      # The hour labels hang from this line under the axis.
      HOUR_LABEL_GAP = 5

      Series = Data.define(:key, :segments)
      Hit = Data.define(:rect, :title)
      Label = Data.define(:x, :y, :text, :key)
      # A name at the right edge and the end of its own line, which the leader joins.
      EndLabel = Data.define(:x, :y, :text, :key, :line_x, :line_y) do
        def leader = [ line_x, line_y, x - LEADER_GAP, y ]
      end

      def initialize(frame:, curves:, hours:, max_w:, grid_step:)
        @frame = frame
        @curves = curves
        @hours = hours
        @max_w = max_w
        @grid_step = grid_step
      end

      def key = @frame.key

      def named? = @frame.named

      def plot
        @plot ||= Plot.new(width: @frame.width, height: @frame.height, margins: @frame.margins,
                           x: @hours, y: 0..@max_w)
      end

      def series = @curves.map { |curve| Series.new(key: curve.key, segments: plot.polylines(curve.points)) }

      def labels
        return [] unless named?

        placed = spread(@curves.filter_map { |curve| end_label(curve) }.sort_by(&:y))
        overflow = placed.map(&:y).max.to_f - (plot.bottom - LABEL_MARGIN)
        return placed if placed.empty? || overflow <= 0

        placed.map { |label| label.with(y: number(label.y - overflow)) }
      end

      def grid_lines = grid.map(&:at)

      def value_labels
        grid.map { |tick| Label.new(x: value_label_x, y: tick.at, text: tick.value.to_s, key: nil) }
      end

      # The unit stands where the top value would, above the last grid line.
      def unit_label = Label.new(x: value_label_x, y: plot.top, text: "W", key: nil)

      # The wide frame has room for the unit, the narrow one only for the number.
      def hour_labels
        plot.x_ticks(@hours.step(@frame.hour_step)).map do |tick|
          text = named? ? "#{tick.value} Uhr" : tick.value.to_s
          Label.new(x: tick.at, y: number(plot.bottom + HOUR_LABEL_GAP), text: text, key: nil)
        end
      end

      def hits
        values = @curves.to_h { |curve| [ curve.key, curve.points.to_h ] }

        @hours.zip(plot.columns(@hours)).map { |hour, column| Hit.new(rect: column, title: title_for(hour, values)) }
      end

      def self.name_of(key) = "Panel #{key.to_s.delete_prefix('pv')}"

      private

      delegate :y, :number, to: :plot, private: true

      def value_label_x = plot.left - VALUE_LABEL_GAP

      def grid = plot.y_ticks(@grid_step.step(@max_w - 1, @grid_step))

      def spread(labels)
        labels.each_with_object([]) do |label, placed|
          previous = placed.last
          too_close = previous && label.y - previous.y < LABEL_GAP
          placed << (too_close ? label.with(y: number(previous.y + LABEL_GAP)) : label)
        end
      end

      def end_label(curve)
        return nil if curve.empty?

        hour, watts = curve.points.max_by(&:first)
        line_y = number(y(watts))
        EndLabel.new(x: number(plot.right + LABEL_OFFSET), y: line_y, text: self.class.name_of(curve.key),
                     key: curve.key, line_x: number(plot.x(hour)), line_y: line_y)
      end

      def title_for(hour, values)
        [
          "#{hour}–#{hour + 1} Uhr",
          *@curves.map { |curve| "#{self.class.name_of(curve.key)} #{watts(values.fetch(curve.key)[hour])}" }
        ].join(" · ")
      end

      def watts(value) = value.nil? ? "keine Daten" : "Ø #{value.round} W"
    end
  end
end
