require "test_helper"
require "sun_calc"

class SunCalcTest < Minitest::Test
  cover "SunCalc*"

  BERLIN_LAT = 52.52
  BERLIN_LON = 13.405
  BERLIN_TZ  = "Europe/Berlin"

  # Reference times come from the NOAA Solar Calculator. The single-pass
  # algorithm in SunCalc is accurate to a few minutes at mid latitudes —
  # we allow ±15 min tolerance to keep the suite robust across years.
  TOLERANCE_SECONDS = 15 * 60

  def test_summer_solstice_berlin
    sunrise = SunCalc.sunrise(date: Date.new(2026, 6, 21), lat: BERLIN_LAT, lon: BERLIN_LON, timezone: BERLIN_TZ)
    sunset  = SunCalc.sunset(date:  Date.new(2026, 6, 21), lat: BERLIN_LAT, lon: BERLIN_LON, timezone: BERLIN_TZ)

    # 04:43 CEST = 02:43 UTC
    assert_in_delta Time.utc(2026, 6, 21, 2, 43).to_i, sunrise.to_i, TOLERANCE_SECONDS
    # 21:33 CEST = 19:33 UTC
    assert_in_delta Time.utc(2026, 6, 21, 19, 33).to_i, sunset.to_i, TOLERANCE_SECONDS
  end

  def test_winter_solstice_berlin
    sunrise = SunCalc.sunrise(date: Date.new(2025, 12, 21), lat: BERLIN_LAT, lon: BERLIN_LON, timezone: BERLIN_TZ)
    sunset  = SunCalc.sunset(date:  Date.new(2025, 12, 21), lat: BERLIN_LAT, lon: BERLIN_LON, timezone: BERLIN_TZ)

    # 08:15 CET = 07:15 UTC
    assert_in_delta Time.utc(2025, 12, 21, 7, 15).to_i, sunrise.to_i, TOLERANCE_SECONDS
    # 15:54 CET = 14:54 UTC
    assert_in_delta Time.utc(2025, 12, 21, 14, 54).to_i, sunset.to_i, TOLERANCE_SECONDS
  end

  def test_daytime_classification
    # Noon in Berlin → day
    assert SunCalc.daytime?(timestamp: Time.utc(2026, 6, 21, 10), lat: BERLIN_LAT, lon: BERLIN_LON, timezone: BERLIN_TZ)
    # Midnight UTC = 02:00 CEST → night
    refute SunCalc.daytime?(timestamp: Time.utc(2026, 6, 21, 0),  lat: BERLIN_LAT, lon: BERLIN_LON, timezone: BERLIN_TZ)
  end

  def test_winter_evening_is_night_in_berlin
    # 17:00 CET = 16:00 UTC, well after sunset on Dec 21
    refute SunCalc.daytime?(timestamp: Time.utc(2025, 12, 21, 16), lat: BERLIN_LAT, lon: BERLIN_LON, timezone: BERLIN_TZ)
  end

  def test_summer_evening_is_still_day_in_berlin
    # 20:30 CEST = 18:30 UTC, before sunset on Jun 21 (~21:33 CEST)
    assert SunCalc.daytime?(timestamp: Time.utc(2026, 6, 21, 18, 30), lat: BERLIN_LAT, lon: BERLIN_LON, timezone: BERLIN_TZ)
  end

  def test_polar_day_returns_true_around_the_clock
    # Above the Arctic Circle on June 21 the sun never sets.
    [ 0, 6, 12, 18, 23 ].each do |hour|
      assert SunCalc.daytime?(timestamp: Time.utc(2026, 6, 21, hour), lat: 78.0, lon: 15.0, timezone: "UTC"),
        "expected polar day at hour #{hour}"
    end
  end

  def test_polar_night_returns_false_around_the_clock
    # Above the Arctic Circle on December 21 the sun never rises.
    [ 0, 6, 12, 18, 23 ].each do |hour|
      refute SunCalc.daytime?(timestamp: Time.utc(2025, 12, 21, hour), lat: 78.0, lon: 15.0, timezone: "UTC"),
        "expected polar night at hour #{hour}"
    end
  end

  def test_solar_event_minutes_utc_clamps_cos_ha_outside_unit_range
    minutes = SunCalc.solar_event_minutes_utc(Date.new(2026, 6, 21), 11.26, 1.0000000000000002, :sunrise)
    refute minutes.nan?
  end

  # Sun position: checked against the geometry that holds at solar noon and
  # solar midnight (elevation = 90° − |lat − declination|, azimuth due south
  # or due north) and at sunrise (elevation at the refraction horizon, azimuth
  # from cos A = sin δ / cos φ). Berlin's solar noon on Jun 21 is ~11:08 UTC.
  def test_position_at_summer_solar_noon_berlin
    position = SunCalc.position(time: Time.utc(2026, 6, 21, 11, 8), lat: BERLIN_LAT, lon: BERLIN_LON)

    assert_in_delta 90 - 52.52 + 23.44, position.elevation, 0.3
    assert_in_delta 180.0, position.azimuth, 1.0
  end

  def test_position_at_winter_solar_noon_berlin
    position = SunCalc.position(time: Time.utc(2025, 12, 21, 11, 4), lat: BERLIN_LAT, lon: BERLIN_LON)

    assert_in_delta 90 - 52.52 - 23.44, position.elevation, 0.3
    assert_in_delta 180.0, position.azimuth, 1.0
  end

  def test_position_at_solar_midnight_points_north_below_the_horizon
    position = SunCalc.position(time: Time.utc(2026, 6, 21, 23, 8), lat: BERLIN_LAT, lon: BERLIN_LON)

    assert_in_delta -(90 - 52.52 - 23.44), position.elevation, 0.5
    assert_operator [ position.azimuth, 360 - position.azimuth ].min, :<, 1.0
  end

  def test_position_at_sunrise_sits_on_the_horizon_in_the_north_east
    sunrise = SunCalc.sunrise(date: Date.new(2026, 6, 21), lat: BERLIN_LAT, lon: BERLIN_LON, timezone: BERLIN_TZ)
    position = SunCalc.position(time: sunrise, lat: BERLIN_LAT, lon: BERLIN_LON)

    assert_in_delta(-0.833, position.elevation, 1.0)
    assert_in_delta 49.2, position.azimuth, 2.0
  end

  def test_position_after_solar_midnight_is_just_east_of_north
    # 23:00 UTC in Berlin is past solar midnight (~22:50 UTC in November): the
    # true solar time has wrapped past 24 h, and the sun has crossed north.
    position = SunCalc.position(time: Time.utc(2026, 11, 5, 23, 0), lat: BERLIN_LAT, lon: BERLIN_LON)

    assert_operator position.azimuth, :>, 0.0
    assert_operator position.azimuth, :<, 10.0
  end

  def test_position_at_the_zenith_is_defined
    eqtime, decl = SunCalc.solar_terms(Date.new(2026, 6, 21), 12.0)
    position = SunCalc.position(time: Time.utc(2026, 6, 21, 12), lat: decl / SunCalc::DEG, lon: -eqtime / 4.0)

    assert_in_delta 90.0, position.elevation, 1e-6
    assert_in_delta 180.0, position.azimuth, 1e-6
  end

  def test_position_moves_west_through_the_afternoon
    noon      = SunCalc.position(time: Time.utc(2026, 6, 21, 11, 8), lat: BERLIN_LAT, lon: BERLIN_LON)
    afternoon = SunCalc.position(time: Time.utc(2026, 6, 21, 15, 8), lat: BERLIN_LAT, lon: BERLIN_LON)

    assert_operator afternoon.azimuth, :>, noon.azimuth + 40
    assert_operator afternoon.elevation, :<, noon.elevation - 10
  end

  def test_position_takes_local_clock_time_with_its_offset
    utc   = SunCalc.position(time: Time.utc(2026, 6, 21, 11, 8), lat: BERLIN_LAT, lon: BERLIN_LON)
    zoned = SunCalc.position(time: Time.find_zone!(BERLIN_TZ).local(2026, 6, 21, 13, 8), lat: BERLIN_LAT, lon: BERLIN_LON)
    fixed = SunCalc.position(time: Time.new(2026, 6, 21, 13, 8, 0, "+02:00"), lat: BERLIN_LAT, lon: BERLIN_LON)

    assert_equal utc, zoned
    assert_equal utc, fixed
  end

  def test_position_leaves_the_given_time_untouched
    time = Time.find_zone!(BERLIN_TZ).local(2026, 6, 21, 13, 8)
    SunCalc.position(time: time, lat: BERLIN_LAT, lon: BERLIN_LON)

    assert_equal "+02:00", time.formatted_offset
  end

  def test_solar_terms_follow_the_hour_within_the_day
    at_noon     = SunCalc.solar_terms(Date.new(2026, 3, 20))
    at_midnight = SunCalc.solar_terms(Date.new(2026, 3, 20), 0.0)
    next_noon   = SunCalc.solar_terms(Date.new(2026, 3, 21))

    assert_equal SunCalc.solar_terms(Date.new(2026, 3, 20), 12.0), at_noon
    # Hour 24 of a day is half a day past its noon. Around the equinox the
    # declination climbs almost linearly, so it lands halfway to the next noon.
    assert_in_delta (at_noon[1] + next_noon[1]) / 2.0, SunCalc.solar_terms(Date.new(2026, 3, 20), 24.0)[1], 1e-4
    assert_operator at_midnight[1], :<, at_noon[1]
  end
end
