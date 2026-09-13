module Solakon
  # The sky as a map: azimuth across, sun elevation up, one field per few
  # degrees, coloured by how much of the offered radiation arrived at the
  # array. Over it the sun's way on the solstices and the equinox, so the
  # winter sky keeps its shape long before any hour has been measured there.
  class YieldMapComponent < ApplicationComponent
    WIDTH = 720
    # Room for the elevation labels, which the phone's media query enlarges.
    LEFT = 38
    RIGHT = 10
    TOP = 16
    # Room under the horizon for the azimuth labels.
    BOTTOM = 30
    # The sky is wider than it is high; stretching the elevation keeps the
    # fields close to square and the low morning sun readable.
    ELEVATION_STRETCH = 1.45
    AXIS_ROUNDING_DEG = 10
    AZIMUTH_LABEL_STEP = 30
    ELEVATION_LABEL_STEP = 10
    CELL_GAP = 0.6
    DOT_RADIUS = 3
    # The hours sit under their dot, the date over the arc's highest point, so
    # the two never meet at noon where both belong to the same place.
    DOT_LABEL_OFFSET = 13
    PATH_LABEL_OFFSET = 9
    # Without a single field or path — no location configured — the map still
    # needs an axis to be drawn on.
    FALLBACK_AZIMUTHS = (90..270)
    FALLBACK_ELEVATION = 60
    COMPASS = { 90 => "Ost", 180 => "Süd", 270 => "West" }.freeze

    Field = Data.define(:x, :y, :width, :height, :fill, :title)
    Gridline = Data.define(:x1, :y1, :x2, :y2, :label_x, :label_y, :text)
    Dot = Data.define(:x, :y, :text, :text_y)
    PathView = Data.define(:label, :points, :dots, :label_x, :label_y)

    def initialize(map:)
      @map = map
    end

    def empty? = @map.bins.empty?

    def view_box = "0 0 #{WIDTH} #{number(TOP + plot_height + BOTTOM)}"

    def fields
      ramp = Ramp.fetch(:diverging)

      @map.bins.map do |bin|
        Field.new(
          x: number(x(bin.azimuth)),
          y: number(y(bin.elevation + bin_size)),
          width: number(bin_size * scale_x - CELL_GAP),
          height: number(bin_size * scale_y - CELL_GAP),
          fill: ramp.color(bin.share.clamp(0.0, 1.0)),
          title: title_for(bin)
        )
      end
    end

    def elevation_lines
      0.step(top_elevation, ELEVATION_LABEL_STEP).map do |elevation|
        Gridline.new(
          x1: LEFT, x2: number(x(azimuths.last)), y1: number(y(elevation)), y2: number(y(elevation)),
          label_x: LEFT - 5, label_y: number(y(elevation) + 3.5), text: "#{elevation}°"
        )
      end
    end

    # Dense labels name every line, sparse ones only the compass points — the
    # phone shows the sparse set.
    def azimuth_lines(density)
      first = (azimuths.first / AZIMUTH_LABEL_STEP.to_f).ceil * AZIMUTH_LABEL_STEP

      first.step(azimuths.last, AZIMUTH_LABEL_STEP).filter_map do |azimuth|
        next if density == :sparse && !COMPASS.key?(azimuth)

        Gridline.new(
          x1: number(x(azimuth)), x2: number(x(azimuth)), y1: TOP, y2: number(y(0)),
          label_x: number(x(azimuth)), label_y: number(y(0) + 14), text: azimuth_label(azimuth, density)
        )
      end
    end

    def paths
      @map.paths.reject { |path| path.points.empty? }.each_with_index.map do |path, index|
        peak = path.points.max_by(&:last)

        PathView.new(
          label: path.label,
          points: path.points.map { |azimuth, elevation| "#{number(x(azimuth))},#{number(y(elevation))}" }.join(" "),
          dots: dots(path, hours: index.zero?),
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

    def bin_size = @map.bin_size

    def scale_x = (WIDTH - LEFT - RIGHT) / (azimuths.last - azimuths.first).to_f

    def scale_y = scale_x * ELEVATION_STRETCH

    def plot_height = top_elevation * scale_y

    def x(azimuth) = LEFT + (azimuth - azimuths.first) * scale_x

    def y(elevation) = TOP + (top_elevation - elevation) * scale_y

    # Wide enough for every field and every path, snapped outwards so the axis
    # labels land on round degrees.
    def azimuths
      @azimuths ||= begin
        values = degrees { |azimuth, _elevation| azimuth } +
                 @map.bins.flat_map { |bin| [ bin.azimuth, bin.azimuth + bin_size ] }
        values.empty? ? FALLBACK_AZIMUTHS : snap_down(values.min)..snap_up(values.max)
      end
    end

    def top_elevation
      @top_elevation ||= begin
        values = degrees { |_azimuth, elevation| elevation } + @map.bins.map { |bin| bin.elevation + bin_size }
        values.empty? ? FALLBACK_ELEVATION : snap_up(values.max)
      end
    end

    def degrees(&) = @map.paths.flat_map { |path| path.points.map(&) }

    def snap_down(value) = (value / AXIS_ROUNDING_DEG.to_f).floor * AXIS_ROUNDING_DEG

    def snap_up(value) = (value / AXIS_ROUNDING_DEG.to_f).ceil * AXIS_ROUNDING_DEG

    # Only the first path carries the hours; on the others the dots would
    # repeat what is already said.
    def dots(path, hours:)
      path.dots.map do |dot|
        Dot.new(x: number(x(dot.azimuth)), y: number(y(dot.elevation)),
                text: hours ? dot.hour.to_s : nil, text_y: number(y(dot.elevation) + DOT_LABEL_OFFSET))
      end
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
