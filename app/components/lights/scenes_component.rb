module Lights
  class ScenesComponent < ApplicationComponent
    # The bridge gives us only the scene NAME, not real colours. Names that say
    # what they look like get a matching palette (English Govee names and their
    # German forms); the first keyword that matches wins.
    PALETTES = [
      [ /aurora|nordlicht|northern/, [ "hsl(150 70% 45%)", "hsl(175 70% 42%)", "hsl(270 55% 55%)" ] ],
      [ /party|disco|rainbow|regenbogen|dance/, [ "hsl(0 85% 58%)", "hsl(48 95% 55%)", "hsl(140 65% 45%)", "hsl(210 85% 55%)", "hsl(285 70% 58%)" ] ],
      [ /sunset|sonnenuntergang|dusk|abend/, [ "hsl(32 95% 58%)", "hsl(335 75% 58%)" ] ],
      [ /sunrise|sonnenaufgang|dawn|morgen/, [ "hsl(48 95% 65%)", "hsl(18 90% 60%)" ] ],
      [ /ocean|\bsea\b|meer|wave|aqua|lagoon|water|wasser/, [ "hsl(195 80% 50%)", "hsl(225 70% 40%)" ] ],
      [ /forest|wald|jungle|dschungel|spring|frühling|grass/, [ "hsl(105 50% 48%)", "hsl(150 55% 30%)" ] ],
      [ /candle|kerze|fire|feuer|flame|kamin/, [ "hsl(40 95% 58%)", "hsl(20 90% 45%)" ] ],
      [ /romantic|romantik|love|liebe|valentin/, [ "hsl(340 80% 65%)", "hsl(355 75% 45%)" ] ],
      [ /reading|lesen|study|work|arbeit|cozy|gemütlich/, [ "hsl(45 90% 88%)", "hsl(36 80% 70%)" ] ],
      [ /night|nacht|sleep|schlaf|moon|mond|\bstar(s|ry)?\b|stern/, [ "hsl(235 50% 32%)", "hsl(265 45% 48%)" ] ],
      [ /snow|schnee|\bice\b|\beis\b|winter|frost/, [ "hsl(195 60% 88%)", "hsl(210 55% 68%)" ] ],
      [ /christmas|weihnacht|xmas/, [ "hsl(355 75% 48%)", "hsl(140 55% 35%)" ] ],
      [ /autumn|herbst|\bfall\b/, [ "hsl(25 80% 50%)", "hsl(45 85% 52%)" ] ]
    ].freeze

    def initialize(light:)
      @light = light
    end

    private

    attr_reader :light

    def scene_gradient(name)
      "linear-gradient(135deg, #{scene_colours(name).join(', ')})"
    end

    def scene_colours(name)
      key = name.downcase
      PALETTES.each { |pattern, colours| return colours if pattern.match?(key) }
      hashed_colours(key)
    end

    # Names without a known keyword still get a stable two-stop gradient.
    def hashed_colours(key)
      sum = key.each_char.sum(&:ord)
      [ "hsl(#{sum % 360} 70% 55%)", "hsl(#{(sum * 7) % 360} 65% 45%)" ]
    end
  end
end
