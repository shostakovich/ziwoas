defmodule ZiwoasWeb.ApiController do
  @moduledoc """
  The JSON the dashboard's charts load: today's power per plug, today's energy
  balance and the daily totals of recent days. Times are Unix seconds (`ts`,
  as the charts plot them) or ISO 8601 dates. The `:api` pipeline answers
  anything but a JSON request with 406.
  """
  use ZiwoasWeb, :controller

  import Ecto.Query

  alias Ziwoas.{Clock, Config, EnergySummary, PowerSeries, Repo}
  alias Ziwoas.Plugs.DailyTotal

  @today_bucket_seconds 60
  @default_days 14

  def today(conn, _params) do
    config = Config.app_config()
    end_ts = Clock.unix_now()
    start_ts = Integer.floor_div(end_ts - 86_400, 3600) * 3600
    series = PowerSeries.from_samples(config.plugs, start_ts, end_ts, @today_bucket_seconds)

    series =
      for plug <- config.plugs do
        points =
          series
          |> PowerSeries.signed_watts_by_ts(plug.id)
          |> Enum.sort_by(fn {ts, _watt} -> ts end)
          |> Enum.map(fn {ts, watt} -> %{ts: ts, avg_power_w: watt} end)

        plug_series(plug, points)
      end

    json(conn, %{series: series})
  end

  def today_summary(conn, _params) do
    summary = EnergySummary.compute_today(Config.app_config())

    json(conn, %{
      date: summary.date,
      produced_wh_today: summary.produced.wh,
      consumed_wh_today: summary.consumed.wh,
      self_consumed_wh_today: summary.self_consumed.wh,
      autarky_ratio: EnergySummary.autarky_ratio(summary),
      self_consumption_ratio: EnergySummary.self_consumption_ratio(summary),
      savings_eur_today: summary.savings_eur
    })
  end

  @doc "`days` (default 14) is clamped to 1..365; anything but an integer is the default."
  def history(conn, params) do
    config = Config.app_config()
    days = days(params["days"])
    cutoff = config.location.timezone |> Clock.today() |> Date.add(-days) |> Date.to_iso8601()

    rows_by_plug =
      from(d in DailyTotal, where: d.date >= ^cutoff, order_by: d.date)
      |> Repo.all()
      |> Enum.group_by(& &1.plug_id)

    series =
      for plug <- config.plugs do
        points =
          rows_by_plug
          |> Map.get(plug.id, [])
          |> Enum.map(&%{date: &1.date, energy_wh: &1.energy_wh})

        plug_series(plug, points)
      end

    json(conn, %{days: days, series: series})
  end

  defp days(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {days, ""} -> days |> max(1) |> min(365)
      _ -> @default_days
    end
  end

  defp days(_value), do: @default_days

  defp plug_series(plug, points),
    do: %{plug_id: plug.id, name: plug.name, role: plug.role, points: points}
end
