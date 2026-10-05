module Solakon
  class YieldMapComponent
    # One drawing of the sky inside a frame. The wide frame keeps the fields
    # close to square and names every third hour; the phone's frame stands
    # taller, so the low morning sun gets room, and names only noon.
    class Sky
      # `hours` lists the hours named at their dots, nil for all of them;
      # `hour_place` sets them outside their arc (:outside) or diagonally over
      # their dot, away from the apex (:corner); `apex_anchor` sets the dates
      # standing over an apex beside it or on it.
      Frame = Data.define(:key, :stretch, :density, :hours, :hour_place, :apex_anchor)

      WIDTH = 720
      # Room for the elevation labels and, under the horizon, the azimuth labels
      # at the size the phone's media query gives them.
      LEFT = 52
      RIGHT = 10
      TOP = 16
      BOTTOM = 36
      MARGINS = { top: TOP, right: RIGHT, bottom: BOTTOM, left: LEFT }.freeze
      AXIS_ROUNDING_DEG = 10
      AZIMUTH_LABEL_STEP = 30
      ELEVATION_LABEL_STEP = 10
      # The phone's larger labels need every other line.
      SPARSE_ELEVATION_LABEL_STEP = 20
      CELL_GAP = 0.6
      DOT_RADIUS = 3
      # The hours stand outside their arc, away from its middle: the highest arc
      # bounds every field, so out there they lie on empty sky.
      DOT_LABEL_OFFSET = 10
      # The phone's large hours stand diagonally off their dot: their bottom
      # corner clears the dot's ring (radius 7, stroke 3) and the arc, which
      # falls away from the apex beneath them.
      CORNER_LABEL_OFFSET = 10
      # How far a label may lean sideways before it is anchored at its dot's side.
      SIDEWAYS = 0.4
      # A sideways label needs this much plot beside its dot, or it would run
      # into the axis labels; it stands over its dot instead.
      LABEL_ROOM = 90
      PATH_LABEL_OFFSET = 9
      ELEVATION_LABEL_GAP = 5
      # The azimuth labels hang from this line under the horizon.
      AZIMUTH_LABEL_GAP = 5
      COMPASS = { 90 => "Ost", 180 => "Süd", 270 => "West" }.freeze

      Field = Data.define(:rect, :fill, :title)
      Gridline = Data.define(:at, :label_at, :text)
      Dot = Data.define(:x, :y, :text, :text_x, :text_y, :anchor, :baseline)
      # `baseline` is the label's dominant-baseline: it hangs under the apex
      # of the lowest arc and stands over every other.
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

      def fields
        ramp = Ramp.fetch(:diverging)

        @map.bins.map do |bin|
          Field.new(
            rect: plot.rect(bin.azimuth..(bin.azimuth + bin_size), bin.elevation..(bin.elevation + bin_size),
                            inset: CELL_GAP),
            fill: ramp.color(bin.share),
            title: title_for(bin)
          )
        end
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

      # Under the lowest arc the sun never stands, so its date hangs there,
      # clear of every field, centred; over the others lies sky the next arc
      # bounds, and there the frame decides whether the date leans aside, clear
      # of the noon hour named left of the apex.
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

      # The stretch decides how tall the plot is, so it is measured before the
      # frame exists rather than asked of it.
      def plot_height = top_elevation * scale_x * @frame.stretch

      # There is always a field — the map is not drawn without one — so there is
      # always something to measure.
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

      # Over the dot and to the side away from the apex: there the arc runs
      # below the label, and the sky above an arc is empty.
      def corner(at_x, at_y, middle_x)
        side = at_x > middle_x ? 1 : -1

        { text_x: number(at_x + (side * CORNER_LABEL_OFFSET)), text_y: number(at_y - CORNER_LABEL_OFFSET),
          anchor: side.positive? ? "start" : "end", baseline: "auto" }
      end

      def named?(hour) = @frame.hours.nil? || @frame.hours.include?(hour)

      # The unit vector from the foot of the arc's middle, on the horizon, to
      # the dot.
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

      def title_for(bin)
        "Azimut #{bin.azimuth}–#{bin.azimuth + bin_size}° · Höhe #{bin.elevation}–#{bin.elevation + bin_size}° · " \
          "Ausbeute #{(bin.share * 100).round} % · #{bin.hours} Stunden · #{bin.first_hour}–#{bin.last_hour} Uhr"
      end
    end
  end
end
