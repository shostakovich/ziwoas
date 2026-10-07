defmodule Ziwoas.Sun.PositionTest do
  use ExUnit.Case, async: true

  alias Ziwoas.{Location, Sun}
  alias Ziwoas.Sun.Position

  @berlin {52.52, 13.405}
  @tromso {69.6492, 18.9553}

  defp minutes_between(a, b), do: abs(DateTime.diff(a, b)) / 60

  describe "sunrise and sunset" do
    test "in Berlin at midsummer, within a few minutes of the almanac" do
      {lat, lon} = @berlin

      # Almanac: 04:43 and 21:33 CEST.
      assert minutes_between(Position.sunrise(~D[2026-06-21], lat, lon), ~U[2026-06-21 02:43:00Z]) <
               3

      assert minutes_between(Position.sunset(~D[2026-06-21], lat, lon), ~U[2026-06-21 19:33:00Z]) <
               3
    end

    test "in Berlin at midwinter, within a few minutes of the almanac" do
      {lat, lon} = @berlin

      # Almanac: 08:15 and 15:54 CET.
      assert minutes_between(Position.sunrise(~D[2026-12-21], lat, lon), ~U[2026-12-21 07:15:00Z]) <
               3

      assert minutes_between(Position.sunset(~D[2026-12-21], lat, lon), ~U[2026-12-21 14:54:00Z]) <
               3
    end

    test "are UTC instants to the microsecond" do
      {lat, lon} = @berlin
      sunrise = Position.sunrise(~D[2026-06-21], lat, lon)

      assert sunrise.time_zone == "Etc/UTC"
      assert {_, 6} = sunrise.microsecond
    end

    test "there are none on Tromsø's polar day and polar night" do
      {lat, lon} = @tromso

      for date <- [~D[2026-06-21], ~D[2026-12-21]] do
        assert Position.sunrise(date, lat, lon) == nil
        assert Position.sunset(date, lat, lon) == nil
      end

      assert Position.cos_hour_angle(~D[2026-06-21], lat) < -1.0
      assert Position.cos_hour_angle(~D[2026-12-21], lat) > 1.0
    end

    test "Tromsø has both again around the equinox" do
      {lat, lon} = @tromso

      sunrise = Position.sunrise(~D[2026-03-20], lat, lon)
      sunset = Position.sunset(~D[2026-03-20], lat, lon)

      assert DateTime.compare(sunrise, sunset) == :lt
      assert_in_delta DateTime.diff(sunset, sunrise) / 3600, 12.3, 0.3
    end
  end

  describe "daytime?" do
    test "follows sunrise and sunset on the local date" do
      {lat, lon} = @berlin

      assert Position.daytime?(~U[2026-06-21 10:00:00Z], lat, lon, "Europe/Berlin")
      refute Position.daytime?(~U[2026-06-21 22:30:00Z], lat, lon, "Europe/Berlin")
      refute Position.daytime?(~U[2026-12-21 06:00:00Z], lat, lon, "Europe/Berlin")
    end

    test "the sunrise instant is day, the sunset instant night" do
      {lat, lon} = @berlin
      sunrise = Position.sunrise(~D[2026-06-21], lat, lon)
      sunset = Position.sunset(~D[2026-06-21], lat, lon)

      refute Position.daytime?(DateTime.add(sunrise, -1), lat, lon, "Europe/Berlin")
      assert Position.daytime?(DateTime.add(sunrise, 1), lat, lon, "Europe/Berlin")
      assert Position.daytime?(DateTime.add(sunset, -1), lat, lon, "Europe/Berlin")
      refute Position.daytime?(DateTime.add(sunset, 1), lat, lon, "Europe/Berlin")
    end

    test "is day around the clock on the polar day, night on the polar night" do
      {lat, lon} = @tromso

      assert Position.daytime?(~U[2026-06-21 23:00:00Z], lat, lon, "Europe/Oslo")
      refute Position.daytime?(~U[2026-12-21 11:00:00Z], lat, lon, "Europe/Oslo")
    end
  end

  describe "position" do
    test "at Berlin's midsummer noon the sun stands south, 61° high" do
      {lat, lon} = @berlin
      position = Position.at(~U[2026-06-21 11:08:00Z], lat, lon)

      assert_in_delta position.azimuth, 180.0, 2.0
      assert_in_delta position.elevation, 60.9, 0.5
    end

    test "rises in the north-east at midsummer, below the horizon at midnight" do
      {lat, lon} = @berlin

      morning = Position.at(~U[2026-06-21 03:00:00Z], lat, lon)
      assert morning.azimuth > 40 and morning.azimuth < 60
      assert morning.elevation > 0 and morning.elevation < 5

      assert Position.at(~U[2026-06-20 23:08:00Z], lat, lon).elevation < -10
    end

    test "Tromsø's midnight sun stays above the horizon in the north" do
      {lat, lon} = @tromso
      midnight = Position.at(~U[2026-06-21 22:44:00Z], lat, lon)

      assert midnight.elevation > 0 and midnight.elevation < 5
      assert midnight.azimuth < 5 or midnight.azimuth > 355
    end

    test "Tromsø's polar night keeps the sun below the horizon at noon" do
      {lat, lon} = @tromso
      assert Position.at(~U[2026-12-21 10:44:00Z], lat, lon).elevation < 0
    end

    test "south of the equator the noon sun stands north" do
      position = Position.at(~U[2026-12-21 01:55:00Z], -33.87, 151.21)

      assert position.azimuth < 10 or position.azimuth > 350
      assert_in_delta position.elevation, 79.6, 1.0
    end

    test "a sub-second part does not move the sun, and the zone does not either" do
      {lat, lon} = @berlin
      utc = Position.at(~U[2026-06-21 11:08:00Z], lat, lon)

      assert Position.at(~U[2026-06-21 11:08:00.999999Z], lat, lon) == utc

      local = DateTime.shift_zone!(~U[2026-06-21 11:08:00Z], "Europe/Berlin")
      assert Position.at(local, lat, lon) == utc
    end
  end

  test "Sun gives the events on the location's clock" do
    {lat, lon} = @berlin
    location = Location.new("Europe/Berlin", lat: lat, lon: lon)

    sunrise = Sun.sunrise(location, ~D[2026-06-21])
    assert sunrise.time_zone == "Europe/Berlin"
    assert sunrise.hour == 4

    tromso = Location.new("Europe/Oslo", lat: elem(@tromso, 0), lon: elem(@tromso, 1))
    assert Sun.sunrise(tromso, ~D[2026-06-21]) == nil
    assert length(Sun.path(tromso, ~D[2026-06-21])) == 96
    assert Sun.path(tromso, ~D[2026-12-21]) == []
  end
end
