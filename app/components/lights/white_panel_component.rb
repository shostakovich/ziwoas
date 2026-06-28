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

    # label => kelvin, all within [min, PRESET_MAX_K].
    def presets
      lo = light.color_temp_min_k
      {
        "Gemütlich" => lo,
        "Neutral"   => ((lo + PRESET_MAX_K) / 2.0 / 100).round * 100,
        "Arbeiten"  => PRESET_MAX_K
      }
    end

    def active?(kelvin) = snapshot.color_temp_k == kelvin
  end
end
