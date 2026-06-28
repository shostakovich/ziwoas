module Lights
  module Types
    include Dry.Types()

    Bool         = Dry::Types["params.bool"]
    Brightness   = Dry::Types["params.integer"].constrained(gteq: 1, lteq: 100)
    # Hardware envelope across all lamps (Floor Lamps reach 2200 K). The exact
    # per-device limit is applied by clamping in SetColorTemp, not here.
    Kelvin       = Dry::Types["params.integer"].constrained(gteq: 1500, lteq: 9000)
    RgbComponent = Dry::Types["params.integer"].constrained(gteq: 0, lteq: 255)
    SceneName    = Dry::Types["params.string"].constrained(min_size: 1)
  end
end
