module Solakon
  # The sky as a map, with the solstice arcs drawn over it: the winter sky keeps
  # its shape long before any hour has been measured there.
  class YieldMapComponent < ApplicationComponent
    WIDTH = 720
    # Room for the elevation labels and, under the horizon, the azimuth labels
    # at the size the phone's media query gives them.
    LEFT = 52
    RIGHT = 10
    TOP = 16
    BOTTOM = 36
    MARGINS = { top: TOP, right: RIGHT, bottom: BOTTOM, left: LEFT }.freeze
    # The sky is wider than it is high; stretching the elevation keeps the
    # fields close to square and the low morning sun readable.
    ELEVATION_STRETCH = 1.45
    AXIS_ROUNDING_DEG = 10
    AZIMUTH_LABEL_STEP = 30
    ELEVATION_LABEL_STEP = 10
    # The phone's larger labels need every other line.
    SPARSE_ELEVATION_LABEL_STEP = 20
    CELL_GAP = 0.6
    DOT_RADIUS = 3
    # The hours stand outside their arc, away from its middle: the highest arc
    # bounds every field, so out there they lie on empty sky. The date stands
    # over the arc's highest point.
    DOT_LABEL_OFFSET = 10
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
    Dot = Data.define(:x, :y, :text, :text_x, :text_y, :anchor)
    PathView = Data.define(:label, :points, :dots, :label_x, :label_y)

    def initialize(map:)
      @map = map
    end

    def empty? = @map.bins.empty?

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
          fill: ramp.color(bin.share.clamp(0.0, 1.0)),
          title: title_for(bin)
        )
      end
    end

    def elevation_label_x = plot.left - ELEVATION_LABEL_GAP

    def elevation_lines(density)
      step = density == :sparse ? SPARSE_ELEVATION_LABEL_STEP : ELEVATION_LABEL_STEP

      0.step(top_elevation, step).map do |elevation|
        at = number(y(elevation))

        Gridline.new(at: at, label_at: at, text: "#{elevation}°")
      end
    end

    def azimuth_lines(density)
      first = Plot.round_up(azimuths.first, to: AZIMUTH_LABEL_STEP)

      first.step(azimuths.last, AZIMUTH_LABEL_STEP).filter_map do |azimuth|
        next if density == :sparse && !COMPASS.key?(azimuth)

        Gridline.new(at: number(x(azimuth)), label_at: azimuth_label_y, text: azimuth_label(azimuth, density))
      end
    end

    def paths
      @map.paths.reject { |path| path.points.empty? }.each_with_index.map do |path, index|
        peak = path.points.max_by(&:last)

        PathView.new(
          label: path.label,
          points: plot.line(path.points),
          dots: dots(path, peak, hours: index.zero?),
          label_x: number(x(peak.first)), label_y: number(y(peak.last) - PATH_LABEL_OFFSET)
        )
      end
    end

    def legend_gradient = Ramp.fetch(:diverging).css_gradient

    def note
      "Ausbeute ist die PV-Leistung geteilt durch die Einstrahlung derselben Stunde, " \
        "bezogen auf die beste je gemessene Stunde. Gezählt werden nur Stunden mit mindestens " \
        "#{Shading::YieldMap::MIN_IRRADIANCE_W_PER_M2} W/m²; ein Feld von #{bin_size}° × #{bin_size}° " \
        "zeigt den Median seiner Stunden und bleibt unter #{Shading::YieldMap::MIN_HOURS} Stunden leer."
    end

    private

    delegate :x, :y, :number, to: :plot, private: true

    def bin_size = @map.bin_size

    def azimuth_label_y = number(y(0) + AZIMUTH_LABEL_GAP)

    def scale_x = (WIDTH - LEFT - RIGHT) / (azimuths.last - azimuths.first).to_f

    # The stretch decides how tall the plot is, so it is measured before the
    # frame exists rather than asked of it.
    def plot_height = top_elevation * scale_x * ELEVATION_STRETCH

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
        out_x, out_y = room_for(at_x, *outwards(at_x, at_y, x(peak.first)))

        Dot.new(x: number(at_x), y: number(at_y), text: (format("%02d:00", dot.hour) if hours),
                text_x: number(at_x + (out_x * DOT_LABEL_OFFSET)), text_y: number(at_y + (out_y * DOT_LABEL_OFFSET)),
                anchor: anchor(out_x))
      end
    end

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

    def azimuth_label(azimuth, density)
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
