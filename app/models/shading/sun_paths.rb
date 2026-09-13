module Shading
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
