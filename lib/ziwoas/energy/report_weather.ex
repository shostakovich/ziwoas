defmodule Ziwoas.Energy.ReportWeather do
  @moduledoc false
  alias Ziwoas.{LocalDay, Location, Weather}
  alias Ziwoas.Weather.{Record, Segment}

  @type day :: %{solar_kwh_per_m2: float | nil, icon: String.t(), daytime: String.t()}
  @type hour :: %{
          ts: integer,
          solar_w_per_m2: float | nil,
          icon: String.t() | nil,
          daytime: String.t() | nil
        }

  @spec daily(Location.t(), Date.t(), Date.t()) :: %{Date.t() => day}
  def daily(location, start_date, end_date) do
    location
    |> historic_records(start_date, end_date)
    |> Enum.group_by(&(&1 |> Weather.local_time(location.timezone) |> DateTime.to_date()))
    |> Map.new(fn {date, records} ->
      segment = day_segment(records)

      {date,
       %{
         solar_kwh_per_m2: day_solar_kwh(records),
         icon: Segment.dominant_icon(segment),
         daytime: Segment.dominant_daytime(segment)
       }}
    end)
  end

  @spec hourly(Location.t(), Date.t(), Date.t()) :: [hour]
  def hourly(location, start_date, end_date) do
    for record <- historic_records(location, start_date, end_date) do
      %{
        ts: DateTime.to_unix(record.timestamp),
        solar_w_per_m2: Weather.solar_w_per_m2(record),
        icon: record.icon,
        daytime: record.daytime
      }
    end
  end

  defp historic_records(%Location{timezone: zone} = location, first, last) do
    from = first |> LocalDay.midnight(zone) |> DateTime.shift_zone!("Etc/UTC")
    to = last |> Date.add(1) |> LocalDay.midnight(zone) |> DateTime.shift_zone!("Etc/UTC")
    Weather.historic_records(location, from, to)
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

    %Segment{label: :day, hours: 0..23, records: pool}
  end
end
