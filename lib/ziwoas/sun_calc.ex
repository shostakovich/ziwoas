defmodule Ziwoas.SunCalc do
  @moduledoc """
  Sunrise/sunset and sun position for a given location, computed locally with
  the NOAA general solar position algorithm
  (https://gml.noaa.gov/grad/solcalc/solareqns.PDF). Sunrise and sunset are a
  single pass at solar noon, accurate to a few minutes at mid latitudes —
  sufficient for deciding whether a weather record falls into "day" or "night".
  Event times are truncated to microseconds.
  """

  @zenith_deg 90.833
  @deg :math.pi() / 180.0

  defmodule Position do
    @moduledoc "Azimuth clockwise from north, elevation above the horizon, both in degrees."
    @enforce_keys [:azimuth, :elevation]
    defstruct @enforce_keys

    @type t :: %__MODULE__{azimuth: float, elevation: float}
  end

  @type event :: :sunrise | :sunset

  @doc "UTC instant of sunrise, or nil on a polar day or night."
  @spec sunrise(Date.t(), number, number) :: DateTime.t() | nil
  def sunrise(date, lat, lon), do: event_time(date, lat, lon, :sunrise)

  @spec sunset(Date.t(), number, number) :: DateTime.t() | nil
  def sunset(date, lat, lon), do: event_time(date, lat, lon, :sunset)

  @doc "Whether the sun is up at an instant, judged on the local date in `timezone`."
  @spec daytime?(DateTime.t(), number, number, String.t()) :: boolean
  def daytime?(%DateTime{} = timestamp, lat, lon, timezone) do
    local_date = timestamp |> DateTime.shift_zone!(timezone) |> DateTime.to_date()
    cos_ha = cos_hour_angle(local_date, lat)

    cond do
      cos_ha < -1.0 ->
        true

      cos_ha > 1.0 ->
        false

      true ->
        at = DateTime.to_unix(timestamp, :microsecond)

        at >= event_microseconds(local_date, lon, cos_ha, :sunrise, :ceil) and
          at < event_microseconds(local_date, lon, cos_ha, :sunset, :ceil)
    end
  end

  @doc """
  Sun position at an instant, in whole seconds: a sub-second part is ignored.
  """
  @spec position(DateTime.t(), number, number) :: Position.t()
  def position(%DateTime{} = time, lat, lon) do
    utc = DateTime.shift_zone!(time, "Etc/UTC")
    minutes = utc.hour * 60 + utc.minute + utc.second / 60.0
    {eqtime, decl} = solar_terms(DateTime.to_date(utc), minutes / 60.0)

    hour_angle = ((minutes + eqtime + 4 * lon) / 4.0 - 180.0) * @deg
    lat_rad = lat * @deg

    sin_elevation =
      :math.sin(lat_rad) * :math.sin(decl) +
        :math.cos(lat_rad) * :math.cos(decl) * :math.cos(hour_angle)

    # atan2 instead of NOAA's acos-and-branch form: the same angle, but it
    # wraps the hour angle by itself and has no pole at the zenith.
    from_north =
      :math.atan2(
        :math.sin(hour_angle),
        :math.cos(hour_angle) * :math.sin(lat_rad) - :math.tan(decl) * :math.cos(lat_rad)
      )

    %Position{
      azimuth: floored_mod(from_north / @deg + 180.0, 360.0),
      elevation: :math.asin(clamp(sin_elevation)) / @deg
    }
  end

  @doc """
  Equation of time (minutes) and declination (radians) for a UTC hour of the
  day; the sunrise/sunset pass evaluates them once at solar noon.
  """
  @spec solar_terms(Date.t(), number) :: {float, float}
  def solar_terms(%Date{} = date, hour_utc \\ 12.0) do
    n = Date.day_of_year(date)
    gamma = 2 * :math.pi() / 365.0 * (n - 1 + (hour_utc - 12) / 24.0)

    eqtime =
      229.18 *
        (0.000075 +
           0.001868 * :math.cos(gamma) -
           0.032077 * :math.sin(gamma) -
           0.014615 * :math.cos(2 * gamma) -
           0.040849 * :math.sin(2 * gamma))

    decl =
      0.006918 -
        0.399912 * :math.cos(gamma) +
        0.070257 * :math.sin(gamma) -
        0.006758 * :math.cos(2 * gamma) +
        0.000907 * :math.sin(2 * gamma) -
        0.002697 * :math.cos(3 * gamma) +
        0.00148 * :math.sin(3 * gamma)

    {eqtime, decl}
  end

  @doc "Below -1 the sun never sets (polar day), above 1 it never rises (polar night)."
  @spec cos_hour_angle(Date.t(), number) :: float
  def cos_hour_angle(date, lat) do
    {_eqtime, decl} = solar_terms(date)
    lat_rad = lat * @deg
    zenith_rad = @zenith_deg * @deg

    (:math.cos(zenith_rad) - :math.sin(lat_rad) * :math.sin(decl)) /
      (:math.cos(lat_rad) * :math.cos(decl))
  end

  @spec solar_event_minutes_utc(Date.t(), number, number, event) :: float
  def solar_event_minutes_utc(date, lon, cos_ha, event) do
    {eqtime, _decl} = solar_terms(date)
    ha_deg = :math.acos(clamp(cos_ha)) / @deg

    case event do
      :sunrise -> 720 - 4 * (lon + ha_deg) - eqtime
      :sunset -> 720 - 4 * (lon - ha_deg) - eqtime
    end
  end

  defp event_time(date, lat, lon, event) do
    cos_ha = cos_hour_angle(date, lat)

    if abs(cos_ha) <= 1.0 do
      DateTime.from_unix!(event_microseconds(date, lon, cos_ha, event, :floor), :microsecond)
    end
  end

  defp event_microseconds(date, lon, cos_ha, event, rounding) do
    offset = solar_event_minutes_utc(date, lon, cos_ha, event) * 60_000_000
    offset = if rounding == :floor, do: floor(offset), else: ceil(offset)

    midnight = date |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.to_unix(:microsecond)
    midnight + offset
  end

  defp clamp(value), do: value |> max(-1.0) |> min(1.0)

  # fmod, then shifted to the sign of the divisor.
  defp floored_mod(x, y) do
    mod = if x == 0.0, do: x, else: :math.fmod(x, y)
    if y * mod < 0, do: mod + y, else: mod
  end
end
