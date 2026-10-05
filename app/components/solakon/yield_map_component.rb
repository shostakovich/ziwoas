module Solakon
  # The sky as a map, with the solstice arcs drawn over it: the winter sky keeps
  # its shape long before any hour has been measured there.
  #
  # Drawn twice, like the sun calendar: wide from a small tablet up, taller for
  # phones, where the wide drawing would shrink to a strip.
  class YieldMapComponent < ApplicationComponent
    # The sky is wider than it is high; stretching the elevation keeps the
    # fields close to square and the low morning sun readable. The phone's
    # frame stretches further and names only noon among the hours; its larger
    # dates start at the apex, so they keep clear of noon's label.
    FRAMES = [
      Sky::Frame.new(key: :wide, stretch: 1.45, density: :dense, hours: nil, apex_anchor: "middle"),
      Sky::Frame.new(key: :narrow, stretch: 2.1, density: :sparse, hours: [ 12 ], apex_anchor: "start")
    ].freeze

    def initialize(map:)
      @map = map
    end

    def empty? = @map.bins.empty?

    def skies = FRAMES.map { |frame| Sky.new(frame: frame, map: @map) }

    def frame_classes(sky) = sky.key == :wide ? "d-none d-sm-block" : "d-sm-none"

    def legend_gradient = Ramp.fetch(:diverging).css_gradient

    def note
      "Ausbeute ist die PV-Leistung geteilt durch die Einstrahlung derselben Stunde, " \
        "bezogen auf die beste je gemessene Stunde. Gezählt werden nur Stunden mit mindestens " \
        "#{Shading::YieldMap::MIN_IRRADIANCE_W_PER_M2} W/m²; ein Feld von #{@map.bin_size}° × #{@map.bin_size}° " \
        "zeigt den Median seiner Stunden und bleibt unter #{Shading::YieldMap::MIN_HOURS} Stunden leer."
    end
  end
end
