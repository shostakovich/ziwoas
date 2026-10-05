module Solakon
  class YieldMapComponent
    class Sky
      # hours: those named at their dots, nil for all; hour_place: :outside the arc or :corner over the dot.
      Frame = Data.define(:key, :stretch, :density, :hours, :hour_place, :apex_anchor)

      WIDTH = 720
      # Room for the phone's larger axis labels.
      LEFT = 52
      RIGHT = 10
      TOP = 16
      BOTTOM = 36
      MARGINS = { top: TOP, right: RIGHT, bottom: BOTTOM, left: LEFT }.freeze
      AXIS_ROUNDING_DEG = 10
      AZIMUTH_LABEL_STEP = 30
      ELEVATION_LABEL_STEP = 10
      SPARSE_ELEVATION_LABEL_STEP = 20
      CELL_GAP = 0.6
      DOT_RADIUS = 3
      # Outside the highest arc lies empty sky, clear of every field.
      DOT_LABEL_OFFSET = 10
      # Clears the phone's dot ring (radius 7, stroke 3) and the arc falling away beneath.
      CORNER_LABEL_OFFSET = 10
      SIDEWAYS = 0.4
      # Less room beside its dot and a sideways label would run into the axis labels.
      LABEL_ROOM = 90
      PATH_LABEL_OFFSET = 9
      ELEVATION_LABEL_GAP = 5
      AZIMUTH_LABEL_GAP = 5
      COMPASS = { 90 => "Ost", 180 => "Süd", 270 => "West" }.freeze

      Field = Data.define(:rect, :bin)
      Fill = Data.define(:color, :fields)
      Gridline = Data.define(:at, :label_at, :text)
      Dot = Data.define(:x, :y, :text, :text_x, :text_y, :anchor, :baseline)
      PathView = Data.define(:label, :points, :dots, :label_x, :label_y, :anchor, :baseline)

      def initialize(frame:, map:)
        @frame = frame
        @map = map
      end

      def key = @frame.key

      def density = @frame.density

      def plot
        @plot ||= Plot.new(width: WIDTH, height: TOP + plot_height + BOTTOM, margins: MARGINS,
                           x: azimuths, y: 0..top_elevation)
      end

      def fills
        ramp = Ramp.fetch(:diverging)

        @map.bins.group_by { |bin| ramp.color(Ramp.level(bin.share)) }.map do |color, bins|
          Fill.new(color: color, fields: bins.map { |bin| field(bin) })
        end
      end

      def title(field)
        bin = field.bin

        "Azimut #{bin.azimuth}–#{bin.azimuth + bin_size}° · Höhe #{bin.elevation}–#{bin.elevation + bin_size}° · " \
          "Ausbeute #{GermanNumber.format(bin.share * 100, unit: '%')} · #{bin.hours} Stunden · #{bin.first_hour}–#{bin.last_hour} Uhr"
      end

      def elevation_label_x = plot.left - ELEVATION_LABEL_GAP

      def elevation_lines(density = self.density)
        step = density == :sparse ? SPARSE_ELEVATION_LABEL_STEP : ELEVATION_LABEL_STEP

        0.step(top_elevation, step).map do |elevation|
          at = number(y(elevation))

          Gridline.new(at: at, label_at: at, text: "#{elevation}°")
        end
      end

      def azimuth_lines
        first = Plot.round_up(azimuths.first, to: AZIMUTH_LABEL_STEP)

        first.step(azimuths.last, AZIMUTH_LABEL_STEP).filter_map do |azimuth|
          next if density == :sparse && !COMPASS.key?(azimuth)

          Gridline.new(at: number(x(azimuth)), label_at: azimuth_label_y, text: azimuth_label(azimuth))
        end
      end

      def paths
        drawn = @map.paths.reject { |path| path.points.empty? }
        lowest = drawn.min_by { |path| path.points.map(&:last).max } if drawn.length > 1

        drawn.each_with_index.map do |path, index|
          path_view(path, hours: index.zero?, beneath: path.equal?(lowest))
        end
      end

      private

      delegate :x, :y, :number, to: :plot, private: true

      def bin_size = @map.bin_size

      def field(bin)
        Field.new(rect: plot.rect(bin.azimuth..(bin.azimuth + bin_size), bin.elevation..(bin.elevation + bin_size),
                                  inset: CELL_GAP),
                  bin: bin)
      end

      # The sun never stands under the lowest arc, so its date hangs there, clear of every field.
      def path_view(path, hours:, beneath:)
        peak = path.points.max_by(&:last)
        offset = beneath ? PATH_LABEL_OFFSET : -PATH_LABEL_OFFSET

        PathView.new(
          label: path.label,
          points: plot.line(path.points),
          dots: dots(path, peak, hours: hours),
          label_x: number(x(peak.first)), label_y: number(y(peak.last) + offset),
          anchor: beneath ? "middle" : @frame.apex_anchor, baseline: beneath ? "hanging" : "auto"
        )
      end

      def azimuth_label_y = number(y(0) + AZIMUTH_LABEL_GAP)

      def scale_x = (WIDTH - LEFT - RIGHT) / (azimuths.last - azimuths.first).to_f

      def plot_height = top_elevation * scale_x * @frame.stretch

      def azimuths
        @azimuths ||= begin
          values = degrees { |azimuth, _elevation| azimuth } +
                   @map.bins.flat_map { |bin| [ bin.azimuth, bin.azimuth + bin_size ] }
          Plot.round_down(values.min, to: AXIS_ROUNDING_DEG)..Plot.round_up(values.max, to: AXIS_ROUNDING_DEG)
        end
      end

      def top_elevation
        @top_elevation ||= Plot.round_up(
          (degrees { |_azimuth, elevation| elevation } + @map.bins.map { |bin| bin.elevation + bin_size }).max,
          to: AXIS_ROUNDING_DEG
        )
      end

      def degrees(&) = @map.paths.flat_map { |path| path.points.map(&) }

      def dots(path, peak, hours:)
        path.dots.map do |dot|
          at_x = x(dot.azimuth)
          at_y = y(dot.elevation)
          place = @frame.hour_place == :corner ? corner(at_x, at_y, x(peak.first)) : outside(at_x, at_y, x(peak.first))

          Dot.new(x: number(at_x), y: number(at_y), text: (format("%02d:00", dot.hour) if hours && named?(dot.hour)), **place)
        end
      end

      def outside(at_x, at_y, middle_x)
        out_x, out_y = room_for(at_x, *outwards(at_x, at_y, middle_x))

        { text_x: number(at_x + (out_x * DOT_LABEL_OFFSET)), text_y: number(at_y + (out_y * DOT_LABEL_OFFSET)),
          anchor: anchor(out_x), baseline: "central" }
      end

      def corner(at_x, at_y, middle_x)
        side = at_x > middle_x ? 1 : -1

        { text_x: number(at_x + (side * CORNER_LABEL_OFFSET)), text_y: number(at_y - CORNER_LABEL_OFFSET),
          anchor: side.positive? ? "start" : "end", baseline: "auto" }
      end

      def named?(hour) = @frame.hours.nil? || @frame.hours.include?(hour)

      def outwards(at_x, at_y, middle_x)
        dx = at_x - middle_x
        dy = at_y - y(0)
        length = Math.hypot(dx, dy)
        return [ 0, -1 ] if length.zero?

        [ dx / length, dy / length ]
      end

      def room_for(at_x, out_x, out_y)
        room = out_x.negative? ? at_x - plot.left : plot.right - at_x
        return [ out_x, out_y ] if out_x.abs < SIDEWAYS || room >= LABEL_ROOM

        [ 0, -1 ]
      end

      def anchor(out_x)
        return "middle" if out_x.abs < SIDEWAYS

        out_x.negative? ? "end" : "start"
      end

      def azimuth_label(azimuth)
        name = COMPASS[azimuth]
        return name if density == :sparse

        [ name, "#{azimuth}°" ].compact.join(" ")
      end
    end
  end
end
