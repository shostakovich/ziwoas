defmodule Ziwoas.EnergyReport.ChartBuilder do
  @moduledoc """
  The chart payloads of the energy report: one bar per day, and a detail chart
  of 5-minute power for up to seven days, or of average daily power beyond.
  Both carry a `:weather` overlay when the location has historic weather for
  the range (`WeatherLoader`).
  """
  alias Ziwoas.{Energy, LocalDay, Location, PowerSeries}
  alias Ziwoas.EnergyReport.{DailyPoint, Store, WeatherLoader}
  alias Ziwoas.Plugs.Roster

  @spec payload(Roster.t(), Location.t(), [DailyPoint.t()], list, {Date.t(), Date.t()}) :: map
  def payload(roster, %Location{timezone: timezone} = location, daily_points, rows, {first, last}) do
    %{
      daily: roster |> daily_chart(daily_points) |> attach_daily_weather(location, first, last),
      detail:
        roster
        |> detail_chart(timezone, rows, first, last)
        |> attach_detail_weather(location, first, last)
    }
  end

  defp daily_chart(roster, points) do
    %{
      labels: Enum.map(points, &(&1.date |> Date.from_iso8601!() |> day_label())),
      produced_kwh: Enum.map(points, &rounded_kwh(&1.produced)),
      consumed_kwh: Enum.map(points, &rounded_kwh(&1.consumed)),
      balance_kwh: Enum.map(points, &rounded_kwh(DailyPoint.balance(&1))),
      consumer_series: consumer_daily_series(roster, Enum.map(points, & &1.date)),
      ratios: Enum.map(points, &ratio_point/1)
    }
  end

  defp ratio_point(%DailyPoint{covered: true} = point) do
    %{
      date: point.date,
      autarky_pct: pct(Energy.ratio_to(point.self_consumed, point.consumed)),
      self_consumption_pct: pct(Energy.ratio_to(point.self_consumed, point.produced))
    }
  end

  defp ratio_point(%DailyPoint{} = point),
    do: %{date: point.date, autarky_pct: nil, self_consumption_pct: nil}

  defp pct(ratio), do: Float.round(ratio * 100, 1)

  defp consumer_daily_series(roster, dates) do
    for plug <- Roster.consumers(roster) do
      rows_by_date = Store.daily_totals_for_plug(plug.id, dates)

      data =
        Enum.map(dates, fn date ->
          case rows_by_date do
            %{^date => row} -> rounded_kwh(Energy.wh(row.energy_wh))
            _ -> 0.0
          end
        end)

      %{plug_id: plug.id, name: plug.name, data: data}
    end
  end

  defp detail_chart(roster, timezone, rows, start_date, end_date) do
    if Date.diff(end_date, start_date) > 6,
      do: daily_power_detail(roster, timezone, rows, start_date, end_date),
      else: sample_detail(roster, timezone, start_date, end_date)
  end

  defp sample_detail(roster, timezone, start_date, end_date) do
    rows =
      Store.sample_rows(
        LocalDay.midnight_unix(start_date, timezone),
        LocalDay.midnight_unix(Date.add(end_date, 1), timezone)
      )

    timestamps = rows |> Enum.map(& &1.bucket_ts) |> Enum.uniq() |> Enum.sort()
    multi_day = start_date != end_date
    series = PowerSeries.from_5min(rows, roster)

    plug_series =
      present_series(roster, fn plug ->
        watts_by_ts = PowerSeries.signed_watts_by_ts(series, plug.id)

        Enum.map(timestamps, fn ts ->
          if watt = watts_by_ts[ts], do: Float.round(watt, 1)
        end)
      end)

    %{
      chart_type: "line",
      labels: Enum.map(timestamps, &detail_label(&1, timezone, multi_day)),
      times: Enum.map(timestamps, &(&1 * 1000)),
      series: plug_series,
      _timestamps: timestamps
    }
  end

  defp daily_power_detail(roster, timezone, rows, start_date, end_date) do
    row_by_plug_and_date = Map.new(rows, &{{&1.plug_id, &1.date}, &1})
    dates = Enum.to_list(Date.range(start_date, end_date))

    plug_series =
      present_series(roster, fn plug ->
        Enum.map(dates, fn date ->
          if row = row_by_plug_and_date[{plug.id, Date.to_iso8601(date)}],
            do: Float.round(row.energy_wh / 24.0, 1)
        end)
      end)

    %{
      chart_type: "bar",
      labels: Enum.map(dates, &day_label/1),
      times: Enum.map(dates, &(LocalDay.midnight_unix(&1, timezone) * 1000)),
      series: plug_series
    }
  end

  # One series per configured plug, dropping plugs without any value.
  defp present_series(roster, data_fun) do
    for plug <- roster.all,
        data = data_fun.(plug),
        Enum.any?(data, &(not is_nil(&1))),
        do: %{plug_id: plug.id, name: plug.name, role: Atom.to_string(plug.role), data: data}
  end

  defp detail_label(ts, timezone, multi_day) do
    format = if multi_day, do: "%d.%m. %H:%M", else: "%H:%M"
    ts |> LocalDay.local_time(timezone) |> Calendar.strftime(format)
  end

  defp day_label(date), do: Calendar.strftime(date, "%d.%m.")

  # Icons only while a bar per day leaves room for one.
  defp attach_daily_weather(chart, location, first, last) do
    case WeatherLoader.daily(location, first, last) do
      daily when map_size(daily) == 0 ->
        chart

      daily ->
        dates = first |> Date.range(last) |> Enum.map(&Date.to_iso8601/1)

        icons =
          if Date.diff(last, first) + 1 <= 7,
            do: Enum.map(dates, &(daily[&1] && Map.take(daily[&1], [:asset_name, :alt]))),
            else: []

        Map.put(chart, :weather, %{
          solar_kwh_per_m2: Enum.map(dates, &(daily[&1] && daily[&1].solar_kwh_per_m2)),
          icons: icons
        })
    end
  end

  defp attach_detail_weather(chart, location, first, last) do
    {timestamps, chart} = Map.pop(chart, :_timestamps, [])

    with "line" <- chart.chart_type,
         [_ | _] <- timestamps,
         [_ | _] = hourly <- WeatherLoader.hourly(location, first, last) do
      zone = location.timezone
      by_hour = Map.new(hourly, &{&1.ts, &1})
      point_at = fn ts -> by_hour[ts - Integer.mod(ts, 3600)] end

      icon_at? =
        if first == last,
          do: fn ts -> Integer.mod(ts, 3600) == 0 end,
          else: fn ts -> match?(%{hour: 12, minute: 0}, LocalDay.local_time(ts, zone)) end

      icons =
        for {ts, index} <- Enum.with_index(timestamps),
            icon_at?.(ts),
            point <- List.wrap(point_at.(ts)),
            do: %{label_index: index, asset_name: point.asset_name, alt: point.alt}

      Map.put(chart, :weather, %{
        solar_w_per_m2: Enum.map(timestamps, &(point_at.(&1) && point_at.(&1).solar_w_per_m2)),
        icons: icons
      })
    else
      _ -> chart
    end
  end

  defp rounded_kwh(energy), do: energy |> Energy.kwh() |> Float.round(3)
end
