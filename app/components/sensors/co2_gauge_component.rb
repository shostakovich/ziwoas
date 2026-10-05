module Sensors
  class Co2GaugeComponent < ApplicationComponent
    MIN_PPM = 400 # outdoor air; a room never reads much lower
    MAX_PPM = 2000
    CENTER  = 60
    RADIUS  = 46
    LEVEL_LABELS = { good: "gut", warn: "erhöht", bad: "schlecht" }.freeze

    FELT_TEXTURE = "https://felt-css.rocu.de/img/felt.svg".freeze
    # Keeps felt-css's 256 px texture tile and 7 px stitch at the size the cards wear them.
    TEXTURE_SIZE = 295
    STITCH_SCALE = 1.15
    STITCH_PITCH = 11

    def initialize(ppm:)
      @ppm = ppm
    end

    def label = "CO₂ #{GermanNumber.format(@ppm, unit: "ppm")}, #{LEVEL_LABELS.fetch(level)}"

    def zones
      bounds = [ MIN_PPM, ReadingPresenter::CO2_WARN_PPM, ReadingPresenter::CO2_BAD_PPM, MAX_PPM ]
      LEVEL_LABELS.keys.zip(bounds.each_cons(2)).map do |zone_level, (from, to)|
        [ zone_level, "M #{point(share(from))} A #{RADIUS} #{RADIUS} 0 0 1 #{point(share(to))}", zone_level == level ]
      end
    end

    def stitches
      count = (Math::PI * RADIUS / STITCH_PITCH).floor
      Array.new(count) do |i|
        at = (i + 0.5) / count
        "translate(#{point(at)}) rotate(#{format('%.1f', at * 180 - 90)}) scale(#{STITCH_SCALE})"
      end
    end

    def needle_angle = format("%.1f", share(@ppm) * 180)

    # Each gauge on a page brings its own defs, so ids must not collide.
    def dom_id(part) = "co2-gauge-#{part}-#{object_id}"

    private

    def level = @level ||= ReadingPresenter.new(SensorReading.new(co2: @ppm)).co2_level

    def point(at)
      angle = Math::PI * (1 - at)
      format("%.1f %.1f", CENTER + RADIUS * Math.cos(angle), CENTER - RADIUS * Math.sin(angle))
    end

    def share(ppm) = (ppm.clamp(MIN_PPM, MAX_PPM) - MIN_PPM).fdiv(MAX_PPM - MIN_PPM)
  end
end
