defmodule Ziwoas.Shading.Builder do
  @moduledoc """
  The shading report of the PV page: every PV hour
  with the irradiance of the same hour and the sun's position at its middle,
  calibrated by the best hour's ratio of power to irradiance.
  """
  import Ecto.Query

  alias Ziwoas.{Location, Repo, Sun, Weather}
  alias Ziwoas.Shading.{DailyProfiles, Hour, PanelCurves, Report, SunPaths, YieldMap}
  alias Ziwoas.Solakon.PvHour
  alias Ziwoas.Weather.Record

  @calibration_min_irradiance_w_per_m2 300
  # "The best hour" as the 95th percentile rather than the single maximum: one
  # hour with an underreported irradiance would otherwise set the scale for
  # every field of the sky.
  @best_hour_percentile 0.95
  @middle_of_hour_s 30 * 60

  @doc "`now` picks the year whose sun paths stand in for every year of hours."
  @spec build(Location.t(), DateTime.t()) :: Report.t()
  def build(%Location{} = location, now) do
    hours = hours(location)
    best_ratio = best_ratio(hours)
    year = now |> DateTime.shift_zone!(location.timezone) |> Map.fetch!(:year)

    %Report{
      map: YieldMap.build(hours, SunPaths.build(location, year), best_ratio),
      profiles: DailyProfiles.build(hours, best_ratio),
      panels: PanelCurves.build(hours)
    }
  end

  defp hours(location) do
    rows = Repo.all(from h in PvHour, order_by: h.started_at)
    irradiance = irradiance_by_time(location, rows)

    for row <- rows do
      position = Sun.position(location, DateTime.add(row.started_at, @middle_of_hour_s))

      %Hour{
        time: DateTime.shift_zone!(row.started_at, location.timezone),
        pv_w: row.pv_power_w,
        irradiance_w_per_m2: Map.get(irradiance, DateTime.to_unix(row.started_at)),
        panels: [row.pv1_power_w, row.pv2_power_w, row.pv3_power_w, row.pv4_power_w],
        azimuth: position && position.azimuth,
        elevation: position && position.elevation
      }
    end
  end

  # Irradiance keyed by the start of the hour it was summed over. The station
  # stamps a record with the end of its hour, so the hour that starts with
  # the last PV hour is stamped one hour later than that.
  defp irradiance_by_time(_location, []), do: %{}

  defp irradiance_by_time(location, rows) do
    if Location.located?(location) do
      from = DateTime.add(hd(rows).started_at, 3600)
      to = DateTime.add(List.last(rows).started_at, 3600)

      Repo.all(
        from r in Record,
          where:
            r.kind == "historic" and r.lat == ^location.lat and r.lon == ^location.lon and
              r.timestamp >= ^from and r.timestamp <= ^to
      )
      |> Enum.reduce(%{}, &put_irradiance/2)
    else
      %{}
    end
  end

  defp put_irradiance(record, out) do
    case Weather.solar_w_per_m2(record) do
      nil ->
        out

      value ->
        started_at = DateTime.add(record.timestamp, -Weather.period_minutes(record) * 60)
        Map.put(out, DateTime.to_unix(started_at), value)
    end
  end

  defp best_ratio(hours) do
    ratios =
      for hour <- hours,
          (hour.irradiance_w_per_m2 || 0.0) >= @calibration_min_irradiance_w_per_m2,
          ratio = Hour.ratio(hour),
          not is_nil(ratio),
          do: ratio

    case ratios do
      [] ->
        nil

      ratios ->
        best = Enum.at(Enum.sort(ratios), floor(length(ratios) * @best_hour_percentile))
        if best > 0, do: best
    end
  end
end
