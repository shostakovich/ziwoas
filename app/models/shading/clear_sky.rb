module Shading
  # Global radiation a cloudless sky would deliver at a sun elevation, after
  # Haurwitz (1945). Only the sun's height enters it — no turbidity, no
  # altitude — which is enough for the line the measured day is read against.
  module ClearSky
    PEAK_W_PER_M2 = 1098.0
    EXTINCTION = 0.059

    extend self

    def w_per_m2(elevation_deg)
      cos_zenith = Math.sin(elevation_deg * Math::PI / 180.0)
      return 0.0 if cos_zenith <= 0

      PEAK_W_PER_M2 * cos_zenith * Math.exp(-EXTINCTION / cos_zenith)
    end
  end
end
