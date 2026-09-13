require "sun_calc"

# The sun as seen from one location. Two adapters answer the same interface:
# the located sun computes, the unknown sun answers empty. Which one a caller
# gets is the location's decision (`Location#sun`), so no reader ever asks
# whether coordinates were configured.
#
# The NOAA algorithm behind it stays private to this module in `SunCalc`.
module Sun
  # Azimuth clockwise from north and elevation above the horizon, both in
  # degrees.
  Position = SunCalc::Position

  # One point of a sun path: where the sun stood, and at which local clock hour.
  Waypoint = Data.define(:hour, :azimuth, :elevation)

  # How finely a sun path is sampled. Fine enough that the curve reads as a
  # curve and that the full hours fall on a sample.
  STEP_HOURS = 0.25

  # The sun over a location whose coordinates are known.
  class Located
    def initialize(location)
      @location = location
    end

    def known? = true

    # Sun position at an instant. The time may carry any zone: only the instant
    # counts, so local clock time and its offset are already in it.
    def position(time) = SunCalc.position(time: time, lat: lat, lon: lon)

    # Local time of the event, or nil on a polar day or night that has neither.
    def sunrise(date) = event(:sunrise, date)

    def sunset(date) = event(:sunset, date)

    def daytime?(time)
      SunCalc.daytime?(timestamp: time, lat: lat, lon: lon, timezone: @location.timezone_name)
    end

    # The sun's way across the sky on one date, sampled over the whole local
    # day and cut at the horizon: what stands below it was never in the sky.
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

  # The sun over a location without coordinates: nobody knows where it stands,
  # so it stands nowhere. Every answer is empty rather than wrong, which is why
  # its callers need no guard of their own.
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
