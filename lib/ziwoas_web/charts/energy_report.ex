defmodule ZiwoasWeb.Charts.EnergyReport do
  @moduledoc false
  use ZiwoasWeb, :verified_routes

  import ZiwoasWeb.Format, only: [day_month: 1]

  alias Ziwoas.{Energy, LocalDay}
  alias Ziwoas.Energy.{Amount, DailyPoint, Report}
  alias ZiwoasWeb.WeatherIcon

  @max_daily_icon_days 7

  @spec payload(Report.t(), String.t()) :: map
  def payload(%Report{} = report, timezone) do
    daily = daily(report)
    detail = detail(report, timezone)
    %{daily: daily, detail: detail, weather_assets: weather_assets([daily, detail])}
  end

  defp daily(%Report{daily_points: points} = report) do
    dates = Enum.map(points, & &1.date)

    %{
      labels: Enum.map(dates, &day_month/1),
      produced_kwh: Enum.map(points, &rounded_kwh(&1.produced)),
      consumed_kwh: Enum.map(points, &rounded_kwh(&1.consumed)),
      balance_kwh: Enum.map(points, &rounded_kwh(DailyPoint.balance(&1))),
      consumer_series:
        for consumer <- report.consumer_daily do
          %{
            plug_id: consumer.plug_id,
            name: consumer.name,
            data: Enum.map(dates, &rounded_kwh(Amount.wh(consumer.wh_by_date[&1] || 0.0)))
          }
        end,
      ratios: Enum.map(points, &ratio_point/1)
    }
    |> put_daily_weather(report.weather.daily, dates)
  end

  defp ratio_point(%DailyPoint{covered: true} = point) do
    %{
      date: Date.to_iso8601(point.date),
      autarky_pct: pct(Energy.autarky_ratio(point)),
      self_consumption_pct: pct(Energy.self_consumption_ratio(point))
    }
  end

  defp ratio_point(%DailyPoint{} = point),
    do: %{date: Date.to_iso8601(point.date), autarky_pct: nil, self_consumption_pct: nil}

  defp pct(ratio), do: Float.round(ratio * 100, 1)

  defp put_daily_weather(chart, weather, _dates) when map_size(weather) == 0, do: chart

  defp put_daily_weather(chart, weather, dates) do
    icons =
      if length(dates) <= @max_daily_icon_days,
        do: Enum.map(dates, &(weather[&1] && icon(weather[&1].icon, weather[&1].daytime))),
        else: []

    Map.put(chart, :weather, %{
      solar_kwh_per_m2: Enum.map(dates, &(weather[&1] && weather[&1].solar_kwh_per_m2)),
      icons: icons
    })
  end

  defp detail(%Report{detail: %{resolution: :daily_mean} = detail}, timezone) do
    %{
      chart_type: "bar",
      labels: Enum.map(detail.dates, &day_month/1),
      times: Enum.map(detail.dates, &(LocalDay.midnight_unix(&1, timezone) * 1000)),
      series: series(detail.series)
    }
  end

  defp detail(%Report{detail: %{resolution: :five_minutes} = detail} = report, timezone) do
    format = if report.start_date == report.end_date, do: "%H:%M", else: "%d.%m. %H:%M"

    %{
      chart_type: "line",
      labels: Enum.map(detail.timestamps, &clock_label(&1, timezone, format)),
      times: Enum.map(detail.timestamps, &(&1 * 1000)),
      series: series(detail.series)
    }
    |> put_detail_weather(detail.timestamps, report, timezone)
  end

  defp series(series) do
    for row <- series,
        do: %{
          plug_id: row.plug_id,
          name: row.name,
          role: Atom.to_string(row.role),
          data: Enum.map(row.watts, &(&1 && Float.round(&1 * 1.0, 1)))
        }
  end

  defp clock_label(ts, timezone, format),
    do: ts |> LocalDay.local_time(timezone) |> Calendar.strftime(format)

  defp put_detail_weather(chart, [], _report, _timezone), do: chart
  defp put_detail_weather(chart, _timestamps, %Report{weather: %{hourly: []}}, _zone), do: chart

  defp put_detail_weather(chart, timestamps, report, timezone) do
    by_hour = Map.new(report.weather.hourly, &{&1.ts, &1})
    point_at = fn ts -> by_hour[ts - Integer.mod(ts, 3600)] end
    icon_at? = detail_icon_at(timezone, report.start_date, report.end_date)

    icons =
      for {ts, index} <- Enum.with_index(timestamps),
          icon_at?.(ts),
          point <- List.wrap(point_at.(ts)),
          do: Map.put(icon(point.icon, point.daytime), :label_index, index)

    Map.put(chart, :weather, %{
      solar_w_per_m2: Enum.map(timestamps, &(point_at.(&1) && point_at.(&1).solar_w_per_m2)),
      icons: icons
    })
  end

  defp detail_icon_at(_zone, day, day), do: fn ts -> Integer.mod(ts, 3600) == 0 end

  defp detail_icon_at(zone, _first, _last),
    do: fn ts -> match?(%{hour: 12, minute: 0}, LocalDay.local_time(ts, zone)) end

  defp icon(code, daytime),
    do: %{asset_name: WeatherIcon.asset_name(code, daytime), alt: code || ""}

  defp weather_assets(charts) do
    charts
    |> Enum.flat_map(&get_in(&1, [Access.key(:weather, %{}), Access.key(:icons, [])]))
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn %{asset_name: name} -> {name, ~p"/images/#{name}"} end)
  end

  defp rounded_kwh(energy), do: energy |> Amount.kwh() |> Float.round(3)
end
