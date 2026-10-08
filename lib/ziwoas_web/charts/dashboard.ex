defmodule ZiwoasWeb.Charts.Dashboard do
  @moduledoc false
  alias Ziwoas.{Clock, Config, Energy, Plugs}
  alias Ziwoas.Plugs.Roster

  @today_bucket_seconds 60
  @history_days 14

  @spec today(Config.t(), integer) :: map
  def today(%Config{plugs: plugs}, end_ts \\ Clock.unix_now()) do
    start_ts = Integer.floor_div(end_ts - 86_400, 3600) * 3600

    series =
      for {plug, points} <- Energy.power_by_plug(plugs, start_ts, end_ts, @today_bucket_seconds) do
        %{
          plug_id: plug.id,
          name: plug.name,
          role: plug.role,
          points: Enum.map(points, fn {ts, watts} -> %{ts: ts, avg_power_w: watts} end)
        }
      end

    %{series: series}
  end

  @spec history(Config.t(), Date.t()) :: map
  def history(%Config{} = config, %Date{} = today) do
    case config |> Config.plug_roster() |> Roster.producer_ids() do
      [] ->
        %{points: nil}

      [producer | _] ->
        points =
          today
          |> Date.add(-@history_days)
          |> Plugs.daily_totals(today, [producer])
          |> Enum.map(&%{date: Date.to_iso8601(&1.date), energy_wh: &1.energy_wh})

        %{points: points}
    end
  end
end
