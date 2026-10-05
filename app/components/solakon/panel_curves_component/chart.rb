module Solakon
  class PanelCurvesComponent
    # Only the wide frame names the lines at their ends; on a phone the names would overlap.
    class Chart
      Frame = Data.define(:key, :width, :height, :margins, :hour_step, :named)

      # The names' line height at their largest, so two never overlap.
      LABEL_GAP = 20
      LABEL_OFFSET = 12
      LEADER_GAP = 3
      # Half that line height: centred names stay clear of the hours.
      LABEL_MARGIN = 10
      VALUE_LABEL_GAP = 5
      UNIT_GAP = 3
      HOUR_LABEL_GAP = 5

      Series = Data.define(:key, :segments)
      EndLabel = Data.define(:x, :y, :text, :key, :line_x, :line_y) do
        def leader = [ line_x, line_y, x - LEADER_GAP, y ]
      end

      def initialize(frame:, curves:, hours:, scale:)
        @frame = frame
        @curves = curves
        @hours = hours
        @scale = scale
      end

      def key = @frame.key

      def named? = @frame.named

      def plot
        @plot ||= Plot.new(width: @frame.width, height: @frame.height, margins: @frame.margins,
                           x: @hours, y: 0..@scale.top)
      end

      def series = @curves.map { |curve| Series.new(key: curve.key, segments: plot.polylines(curve.points)) }

      def labels
        return [] unless named?

        placed = spread(@curves.filter_map { |curve| end_label(curve) }.sort_by(&:y))
        overflow = placed.map(&:y).max.to_f - (plot.bottom - LABEL_MARGIN)
        return placed if placed.empty? || overflow <= 0

        placed.map { |label| label.with(y: number(label.y - overflow)) }
      end

      def grid_lines = plot.grid_lines(grid_values)

      def value_labels = plot.value_labels(grid_values, gap: VALUE_LABEL_GAP)

      def unit_label = Plot::Label.new(x: plot.left - VALUE_LABEL_GAP + UNIT_GAP, y: plot.top, text: "W")

      def hour_labels
        pattern = named? ? "%02d:00" : "%02d"

        plot.x_ticks(@hours.select { |hour| (hour % @frame.hour_step).zero? }).map do |tick|
          Plot::Label.new(x: tick.at, y: plot.bottom + HOUR_LABEL_GAP, text: format(pattern, tick.value))
        end
      end

      def hits
        values = @curves.to_h { |curve| [ curve.key, curve.points.to_h ] }

        plot.hits(@hours, @hours.map { |hour| title_for(hour, values) })
      end

      def self.name_of(key) = "Panel #{key.to_s.delete_prefix('pv')}"

      private

      delegate :y, :number, to: :plot, private: true

      def grid_values = 0.step(@scale.top, @scale.step)

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

      def watts(value) = value.nil? ? "keine Daten" : "Ø #{GermanNumber.format(value, unit: "W")}"
    end
  end
end
