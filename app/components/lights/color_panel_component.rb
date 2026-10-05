module Lights
  class ColorPanelComponent < ApplicationComponent
    SWATCHES = %w[#ff4d4d #ff7a3d #ffd43b #43d97f #22b8cf #4d7cff #7c5cff #ff6bd6].freeze

    def initialize(snapshot:)
      @snapshot = snapshot
    end

    private

    attr_reader :snapshot

    # The swatch the lamp shows right now, if it shows a colour at all.
    def selected?(hex) = !snapshot.white? && snapshot.color_hex == hex

    # A colour the lamp shows that none of the swatches has, picked on the wheel.
    def custom? = !snapshot.white? && !SWATCHES.include?(snapshot.color_hex)
  end
end
