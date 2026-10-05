module Lights
  class WhitePanelComponent < ApplicationComponent
    PRESET_MAX_K = 5400

    def initialize(snapshot:)
      @snapshot = snapshot
    end

    private

    attr_reader :snapshot

    def light = snapshot.light

    def slider_value = snapshot.color_temp_k || light.color_temp_min_k

    # Clamped into the lamp's range, or SetColorTemp would clamp a preset to a value the active button doesn't show.
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

    def share(kelvin)
      span = light.color_temp_max_k - light.color_temp_min_k
      return 0 unless span.positive?
      (kelvin - light.color_temp_min_k).fdiv(span).round(4)
    end
  end
end
