defmodule Ziwoas.EnergyReport.WeatherLoader do
  @moduledoc """
  The weather behind the energy report's chart overlays: `historic` records
  of the configured location between the local midnights of a date range. A
  location without coordinates has none.
  """
  import Ecto.Query

  alias Ziwoas.{LocalDay, Location, Repo, Weather}
  alias Ziwoas.Weather.{Record, Segment}

  @type day :: %{solar_kwh_per_m2: float | nil, asset_name: String.t(), alt: String.t()}
  @type hour :: %{
          ts: integer,
          solar_w_per_m2: float | nil,
          asset_name: String.t(),
          alt: String.t()
        }

  @doc "Per local date (ISO string) with records: summed solar kWh/m², icon and its alt text."
  @spec daily(Location.t(), Date.t(), Date.t()) :: %{String.t() => day}
  def daily(location, start_date, end_date) do
    location
    |> historic_records(start_date, end_date)
    |> Enum.group_by(&(&1 |> Weather.local_time(location.timezone) |> DateTime.to_date()))
    |> Map.new(fn {date, records} ->
      segment = day_segment(records)

      {Date.to_iso8601(date),
       %{
         solar_kwh_per_m2: day_solar_kwh(records),
         asset_name: Segment.asset_name(segment),
         alt: Segment.dominant_icon(segment)
       }}
    end)
  end

  @doc "One point per record, `ts` its timestamp (the end of its hour) in Unix seconds."
  @spec hourly(Location.t(), Date.t(), Date.t()) :: [hour]
  def hourly(location, start_date, end_date) do
    for record <- historic_records(location, start_date, end_date) do
      %{
        ts: DateTime.to_unix(record.timestamp),
        solar_w_per_m2: Weather.solar_w_per_m2(record),
        asset_name: Weather.asset_name(record),
        alt: record.icon || ""
      }
    end
  end

  defp historic_records(%Location{lat: lat, lon: lon, timezone: zone} = location, first, last) do
    if Location.located?(location) do
      from_ts = first |> LocalDay.midnight(zone) |> DateTime.shift_zone!("Etc/UTC")
      to_ts = last |> Date.add(1) |> LocalDay.midnight(zone) |> DateTime.shift_zone!("Etc/UTC")

      Repo.all(
        from r in Record,
          where:
            r.kind == "historic" and r.lat == ^lat and r.lon == ^lon and
              r.timestamp >= ^from_ts and r.timestamp < ^to_ts,
          order_by: r.timestamp
      )
    else
      []
    end
  end

  # `historic` solar is kWh/m² per 60-minute period, so the day's total is the sum.
  defp day_solar_kwh(records) do
    case for(%Record{solar: solar} <- records, not is_nil(solar), do: solar) do
      [] -> nil
      values -> Float.round(Enum.sum(values) * 1.0, 3)
    end
  end

  defp day_segment(records) do
    pool =
      case Enum.filter(records, &(&1.daytime == "day")) do
        [] -> records
        daytime -> daytime
      end

    %Segment{label: "day", hours: 0..23, records: pool}
  end
end
