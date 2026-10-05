module Solakon
  # Drawn twice: on a phone the wide drawing would shrink to a strip.
  class YieldMapComponent < ApplicationComponent
    include ChartParts

    # Stretching the elevation keeps the fields close to square and the low morning sun readable.
    FRAMES = [
      Sky::Frame.new(key: :wide, stretch: 1.45, density: :dense, hours: nil, hour_place: :outside, apex_anchor: "middle"),
      Sky::Frame.new(key: :narrow, stretch: 2.1, density: :sparse, hours: [ 12 ], hour_place: :corner, apex_anchor: "start")
    ].freeze

    def initialize(map:)
      @map = map
    end

    def empty? = @map.bins.empty?

    def skies = FRAMES.map { |frame| Sky.new(frame: frame, map: @map) }

    def legend_gradient = Ramp.fetch(:diverging).css_gradient

    def note
      "Ausbeute ist die PV-Leistung geteilt durch die Einstrahlung derselben Stunde, " \
        "bezogen auf die beste je gemessene Stunde. Gezählt werden nur Stunden mit mindestens " \
        "#{Shading::YieldMap::MIN_IRRADIANCE_W_PER_M2} W/m²; ein Feld von #{@map.bin_size}° × #{@map.bin_size}° " \
        "zeigt den Median seiner Stunden und bleibt unter #{Shading::YieldMap::MIN_HOURS} Stunden leer."
    end
  end
end
