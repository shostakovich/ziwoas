# Day/night window for one instant. Guarantees hours_until_sunrise is measured
# against the *next* sunrise (today's if we are before it, tomorrow's if past),
# so the night energy budget never collapses to zero late at night.
class SunWindow
  FALLBACK_SUNRISE_HOUR = 6
  FALLBACK_SUNSET_HOUR  = 20

  def self.for(now:, weather:, timezone:)
    date = now.to_date
    if weather
      sunrise = SunCalc.sunrise(date: date, lat: weather.lat, lon: weather.lon, timezone: timezone)
      sunset  = SunCalc.sunset(date: date, lat: weather.lat, lon: weather.lon, timezone: timezone)
      next_sr = SunCalc.sunrise(date: date + 1, lat: weather.lat, lon: weather.lon, timezone: timezone)
    end
    sunrise ||= now.change(hour: FALLBACK_SUNRISE_HOUR, min: 0)
    sunset  ||= now.change(hour: FALLBACK_SUNSET_HOUR, min: 0)
    next_sr ||= sunrise + 1.day

    new(now: now, sunrise: sunrise, sunset: sunset,
        next_sunrise: now < sunrise ? sunrise : next_sr)
  end

  def initialize(now:, sunrise:, sunset:, next_sunrise:)
    @now = now
    @sunrise = sunrise
    @sunset = sunset
    @next_sunrise = next_sunrise
  end

  def daytime?
    @now >= @sunrise && @now < @sunset
  end

  def hours_until_sunrise
    [ (@next_sunrise - @now) / 3600.0, 0.0 ].max
  end
end
