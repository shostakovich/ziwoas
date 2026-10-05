module Lights
  # White-light panel: the Kelvin slider plus three presets, both driven by the
  # lamp's own colorTemperatureK range (Floor Lamps reach down to 2200 K). The
  # presets span min..PRESET_MAX_K so "Gemütlich" always lands on the warmest
  # value the lamp supports.
  class WhitePanelComponent < ApplicationComponent
    PRESET_MAX_K = 5400

    def initialize(snapshot:)
      @snapshot = snapshot
    end

    private

    attr_reader :snapshot

    def light = snapshot.light

    def slider_value = snapshot.color_temp_k || light.color_temp_min_k

    # label => kelvin. The high point is PRESET_MAX_K (so "Arbeiten" stays a
    # comfortable working white, not the lamp's coldest), but clamped into the
    # lamp's advertised range so a preset can never fall outside the slider —
    # which would let SetColorTemp clamp it to a different value than the active
    # button shows.
    def presets
      lo = light.color_temp_min_k
      hi = PRESET_MAX_K.clamp(light.color_temp_range)
      {
        "Gemütlich" => lo,
        "Neutral"   => ((lo + hi) / 2.0 / 100).round * 100,
        "Arbeiten"  => hi
      }
    end

    def active?(kelvin) = snapshot.color_temp_k == kelvin

    def kelvin(value) = "#{GermanNumber.format(value)} K"

    # Where a preset sits on the slider, as a share of its range (0..1).
    def share(kelvin)
      span = light.color_temp_max_k - light.color_temp_min_k
      return 0 unless span.positive?
      (kelvin - light.color_temp_min_k).fdiv(span).round(4)
    end
  end
end
