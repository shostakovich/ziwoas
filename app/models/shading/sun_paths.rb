require "sun_calc"

module Shading
  # The sun's way across the sky on the two solstices and the equinox, so the
  # map keeps its shape where no hour was ever measured — the winter sky above
  # all, which the data will not reach for months.
  class SunPaths
    DATES = [
      [ "21.6.", [ 6, 21 ] ],
      [ "21.3. / 23.9.", [ 9, 23 ] ],
      [ "21.12.", [ 12, 21 ] ]
    ].freeze

    HOURS = (3.0..21.5)
    STEP_HOURS = 0.25
    DOT_HOURS = [ 6, 9, 12, 15, 18 ].freeze

    def initialize(zone:, lat:, lon:)
      @zone = ActiveSupport::TimeZone[zone]
      @lat = lat
      @lon = lon
    end

    def build(year)
      return [] if @lat.nil? || @lon.nil?

      DATES.map do |label, (month, day)|
        date = Date.new(year, month, day)
        Path.new(label: label, points: points(date), dots: dots(date))
      end
    end

    private

    def points(date)
      HOURS.step(STEP_HOURS).filter_map do |hour|
        position = position(date, hour)
        [ position.azimuth, position.elevation ] if position.elevation > 0
      end
    end

    def dots(date)
      DOT_HOURS.filter_map do |hour|
        position = position(date, hour)
        Dot.new(hour: hour, azimuth: position.azimuth, elevation: position.elevation) if position.elevation > 0
      end
    end

    # The hour is local clock time; only the instant reaches the algorithm, so
    # the zone's offset on that date is already in it.
    def position(date, hour)
      SunCalc.position(time: date.in_time_zone(@zone) + hour.hours, lat: @lat, lon: @lon)
    end
  end
end
