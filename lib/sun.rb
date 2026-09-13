require "sun_calc"

# Two adapters answer the same interface, and the location picks between them,
# so no reader asks whether coordinates were configured.
module Sun
  Position = SunCalc::Position

  # One point of a sun path: where the sun stood, and at which local clock hour.
  Waypoint = Data.define(:hour, :azimuth, :elevation)

  # How finely a sun path is sampled. Fine enough that the curve reads as a
  # curve and that the full hours fall on a sample.
  STEP_HOURS = 0.25

  class Located
    def initialize(location)
      @location = location
    end

    def known? = true

    def position(time) = SunCalc.position(time: time, lat: lat, lon: lon)

    # Local time of the event, or nil on a polar day or night that has neither.
    def sunrise(date) = event(:sunrise, date)

    def sunset(date) = event(:sunset, date)

    def daytime?(time)
      SunCalc.daytime?(timestamp: time, lat: lat, lon: lon, timezone: @location.timezone_name)
    end

    def path(date)
      midnight = date.in_time_zone(zone)

      0.0.step(24.0 - STEP_HOURS, STEP_HOURS).filter_map do |hour|
        at = position(midnight + hour.hours)
        Waypoint.new(hour: hour, azimuth: at.azimuth, elevation: at.elevation) if at.elevation.positive?
      end
    end

    private

    def lat = @location.lat

    def lon = @location.lon

    def zone = @location.timezone

    def event(name, date)
      SunCalc.public_send(name, date: date, lat: lat, lon: lon, timezone: @location.timezone_name)&.in_time_zone(zone)
    end
  end

  class Unknown
    def known? = false

    def position(_time) = nil

    def sunrise(_date) = nil

    def sunset(_date) = nil

    def path(_date) = []

    # Day, because a weather icon has to pick one and the day variant is what
    # an unplaced house showed before it had a sun at all.
    def daytime?(_time) = true
  end
end
