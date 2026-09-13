require "date"
require "tzinfo"

# Sunrise/sunset and sun position for a given location, computed locally with
# the NOAA general solar position algorithm
# (https://gml.noaa.gov/grad/solcalc/solareqns.PDF). Sunrise and sunset are a
# single pass at solar noon, accurate to a few minutes at mid latitudes —
# sufficient for deciding whether a weather record falls into "day" or "night".
module SunCalc
  ZENITH_DEG = 90.833
  DEG = Math::PI / 180.0

  # Azimuth clockwise from north, elevation above the horizon, both in degrees.
  Position = Data.define(:azimuth, :elevation)

  module_function

  def sunrise(date:, lat:, lon:, timezone:)
    event_time(date, lat, lon, timezone, :sunrise)
  end

  def sunset(date:, lat:, lon:, timezone:)
    event_time(date, lat, lon, timezone, :sunset)
  end

  def daytime?(timestamp:, lat:, lon:, timezone:)
    tz = TZInfo::Timezone.get(timezone)
    local_date = tz.utc_to_local(timestamp.to_time.utc).to_date
    cos_ha = cos_hour_angle(local_date, lat)

    return true  if cos_ha < -1.0 # polar day
    return false if cos_ha >  1.0 # polar night

    sr = event_time(local_date, lat, lon, timezone, :sunrise)
    ss = event_time(local_date, lat, lon, timezone, :sunset)
    timestamp >= sr && timestamp < ss
  end

  # Sun position at an instant. The time may carry any zone: only the instant
  # counts, so local clock time and its DST offset are already in it.
  def position(time:, lat:, lon:)
    utc = time.getutc
    minutes = utc.hour * 60 + utc.min + utc.sec / 60.0
    eqtime, decl = solar_terms(utc.to_date, minutes / 60.0)

    hour_angle = (minutes + eqtime + 4 * lon) / 4.0 - 180.0
    lat_rad = lat * DEG
    cos_zenith = Math.sin(lat_rad) * Math.sin(decl) +
                 Math.cos(lat_rad) * Math.cos(decl) * Math.cos(hour_angle * DEG)
    zenith = Math.acos(cos_zenith.clamp(-1.0, 1.0))

    cos_azimuth = (Math.sin(lat_rad) * Math.cos(zenith) - Math.sin(decl)) /
                  (Math.cos(lat_rad) * Math.sin(zenith))
    from_south = Math.acos(cos_azimuth.clamp(-1.0, 1.0)) / DEG
    azimuth = hour_angle > 0 ? (from_south + 180.0) % 360 : (540.0 - from_south) % 360

    Position.new(azimuth: azimuth, elevation: 90.0 - zenith / DEG)
  end

  def event_time(date, lat, lon, timezone, event)
    cos_ha = cos_hour_angle(date, lat)
    return nil if cos_ha.abs > 1.0

    minutes = solar_event_minutes_utc(date, lon, cos_ha, event)
    Time.utc(date.year, date.month, date.day, 0, 0, 0) + minutes * 60
  end

  # Equation of time (minutes) and declination (radians) for a UTC hour of the
  # day; the sunrise/sunset pass evaluates them once at solar noon.
  def solar_terms(date, hour_utc = 12.0)
    n = date.yday
    gamma = 2 * Math::PI / 365.0 * (n - 1 + (hour_utc - 12) / 24.0)

    eqtime = 229.18 * (
      0.000075 +
      0.001868 * Math.cos(gamma) -
      0.032077 * Math.sin(gamma) -
      0.014615 * Math.cos(2 * gamma) -
      0.040849 * Math.sin(2 * gamma)
    )

    decl =
      0.006918 -
      0.399912 * Math.cos(gamma) +
      0.070257 * Math.sin(gamma) -
      0.006758 * Math.cos(2 * gamma) +
      0.000907 * Math.sin(2 * gamma) -
      0.002697 * Math.cos(3 * gamma) +
      0.00148  * Math.sin(3 * gamma)

    [ eqtime, decl ]
  end

  def cos_hour_angle(date, lat)
    _, decl = solar_terms(date)
    lat_rad = lat * Math::PI / 180.0
    zenith_rad = ZENITH_DEG * Math::PI / 180.0
    (Math.cos(zenith_rad) - Math.sin(lat_rad) * Math.sin(decl)) /
      (Math.cos(lat_rad) * Math.cos(decl))
  end

  def solar_event_minutes_utc(date, lon, cos_ha, event)
    eqtime, _ = solar_terms(date)
    ha_deg = Math.acos(cos_ha.clamp(-1.0, 1.0)) * 180.0 / Math::PI
    case event
    when :sunrise then 720 - 4 * (lon + ha_deg) - eqtime
    when :sunset  then 720 - 4 * (lon - ha_deg) - eqtime
    end
  end
end
