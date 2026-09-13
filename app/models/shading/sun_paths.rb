module Shading
  # The sun's way across the sky on the two solstices and the equinox, so the
  # map keeps its shape where no hour was ever measured — the winter sky above
  # all, which the data will not reach for months.
  #
  # Which days are worth drawing and where the hours get marked is this map's
  # choice; the sun path itself belongs to the sun.
  class SunPaths
    DATES = [
      [ "21.6.", [ 6, 21 ] ],
      [ "21.3. / 23.9.", [ 9, 23 ] ],
      [ "21.12.", [ 12, 21 ] ]
    ].freeze

    DOT_HOURS = [ 6, 9, 12, 15, 18 ].freeze

    def initialize(location:)
      @location = location
    end

    # A date on which the sun never rose leaves no path — a polar winter, or a
    # location whose coordinates nobody configured.
    def build(year)
      DATES.filter_map do |label, (month, day)|
        waypoints = @location.sun.path(Date.new(year, month, day))
        Path.new(label: label, points: points(waypoints), dots: dots(waypoints)) if waypoints.any?
      end
    end

    private

    def points(waypoints) = waypoints.map { |waypoint| [ waypoint.azimuth, waypoint.elevation ] }

    def dots(waypoints)
      waypoints.filter_map do |waypoint|
        hour = waypoint.hour.to_i
        next unless waypoint.hour == hour && DOT_HOURS.include?(hour)

        Dot.new(hour: hour, azimuth: waypoint.azimuth, elevation: waypoint.elevation)
      end
    end
  end
end
