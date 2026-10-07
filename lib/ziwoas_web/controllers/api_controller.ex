defmodule ZiwoasWeb.ApiController do
  @moduledoc """
  The JSON API (Rails' `ApiController` and its jbuilder views), byte-identical
  through `Ziwoas.RubyJSON`. Like Rails without a JSON Accept header, the
  `:api` pipeline answers 406.
  """
  use ZiwoasWeb, :controller

  import Ecto.Query

  alias Ziwoas.{Clock, Config, EnergySummary, PowerSeries, Repo, RubyJSON, RubyNumeric}
  alias Ziwoas.Plugs.DailyTotal

  @today_bucket_seconds 60

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
          |> Enum.map(fn {ts, watt} -> [{"ts", ts}, {"avg_power_w", watt}] end)

        plug_series(plug, points)
      end

    render_json(conn, [{"series", series}])
  end

  def today_summary(conn, _params) do
    summary = EnergySummary.compute_today(Config.app_config())

    render_json(conn, [
      {"date", summary.date},
      {"produced_wh_today", summary.produced.wh},
      {"consumed_wh_today", summary.consumed.wh},
      {"self_consumed_wh_today", summary.self_consumed.wh},
      {"autarky_ratio", EnergySummary.autarky_ratio(summary)},
      {"self_consumption_ratio", EnergySummary.self_consumption_ratio(summary)},
      {"savings_eur_today", summary.savings_eur}
    ])
  end

  @doc "`days` (default 14) is read like Ruby's `to_i` and clamped to 1..365."
  def history(conn, params) do
    config = Config.app_config()
    days = params |> Map.get("days", "14") |> days()
    zone = config.location.timezone
    cutoff = zone |> Clock.today() |> Date.add(-days) |> Date.to_iso8601()

    rows_by_plug =
      from(d in DailyTotal, where: d.date >= ^cutoff, order_by: d.date)
      |> Repo.all()
      |> Enum.group_by(& &1.plug_id)

    series =
      for plug <- config.plugs do
        points =
          rows_by_plug
          |> Map.get(plug.id, [])
          |> Enum.map(&[{"date", &1.date}, {"energy_wh", &1.energy_wh}])

        plug_series(plug, points)
      end

    render_json(conn, [{"days", days}, {"series", series}])
  end

  # Rails calls `to_i` on whatever arrived; only a string has one.
  defp days(value) when is_binary(value), do: value |> RubyNumeric.to_i() |> max(1) |> min(365)

  defp days(value),
    do: raise(ArgumentError, "undefined method 'to_i' for #{inspect(value)}")

  defp plug_series(plug, points),
    do: [{"plug_id", plug.id}, {"name", plug.name}, {"role", plug.role}, {"points", points}]

  defp render_json(conn, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, RubyJSON.encode!(payload))
  end
end
