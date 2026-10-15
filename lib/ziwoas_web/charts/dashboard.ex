defmodule ZiwoasWeb.Charts.Dashboard do
  @moduledoc false
  import ZiwoasWeb.Format, only: [number: 2, day_month: 1]

  alias Ziwoas.{Clock, Config, Energy, LocalDay, Plugs}
  alias Ziwoas.Plugs.Roster

  @today_bucket_seconds 60
  @history_days 14
  # Below this an hour's yield is the inverter's night-time noise, not production.
  @min_produced_kwh 0.02

  @spec today(Config.t(), integer) :: %{power: map, energy: map}
  def today(%Config{plugs: plugs} = config, end_ts \\ Clock.unix_now()) do
    start_ts = hour(end_ts - 86_400)
    by_plug = Energy.power_by_plug(plugs, start_ts, end_ts, @today_bucket_seconds)
    producer_ids = config |> Config.plug_roster() |> Roster.producer_ids()
    %{power: power(by_plug), energy: energy(by_plug, producer_ids, start_ts, end_ts)}
  end

  @doc "Whether any plug reported in the window."
  @spec measured?(%{power: map}) :: boolean
  def measured?(%{power: %{series: series}}), do: Enum.any?(series, &(&1.points != []))

  defp power(by_plug) do
    %{
      series:
        for {plug, points} <- by_plug do
          %{
            plug_id: plug.id,
            name: plug.name,
            role: plug.role,
            points: Enum.map(points, fn {ts, watts} -> [ts, watts] end)
          }
        end
    }
  end

  defp energy(by_plug, producer_ids, start_ts, end_ts) do
    hours = Enum.to_list(start_ts..hour(end_ts)//3600)
    {producers, consumers} = Enum.split_with(by_plug, fn {plug, _} -> plug.id in producer_ids end)

    produced =
      producers
      |> Enum.map(fn {_plug, points} -> kwh_by_hour(points) end)
      |> Enum.reduce(%{}, &Map.merge(&1, &2, fn _hour, a, b -> a + b end))

    %{
      hours: Enum.map(hours, &(&1 * 1000)),
      produced_kwh: Enum.map(hours, &produced_kwh(produced[&1])),
      consumers:
        for {plug, points} <- consumers do
          by_hour = kwh_by_hour(points)
          %{plug_id: plug.id, name: plug.name, kwh: Enum.map(hours, &rounded(by_hour[&1]))}
        end
    }
  end

  defp kwh_by_hour(points) do
    points
    |> Enum.group_by(fn {ts, _watts} -> hour(ts) end, fn {_ts, watts} -> watts / 60 end)
    |> Map.new(fn {hour, wh} -> {hour, Enum.sum(wh) / 1000} end)
  end

  defp produced_kwh(kwh) when is_number(kwh) and kwh >= @min_produced_kwh, do: rounded(kwh)
  defp produced_kwh(_kwh), do: 0.0

  defp rounded(nil), do: 0.0
  defp rounded(kwh), do: Float.round(kwh * 1.0, 3)

  defp hour(ts), do: Integer.floor_div(ts, 3600) * 3600

  @spec energy_rows(map, String.t()) :: [map]
  def energy_rows(%{hours: hours, produced_kwh: produced, consumers: consumers}, zone) do
    consumed = consumers |> Enum.map(& &1.kwh) |> Enum.zip_with(&Enum.sum/1)
    consumed = if consumed == [], do: List.duplicate(0.0, length(hours)), else: consumed

    [hours, produced, consumed]
    |> Enum.zip_with(fn [ms, produced, consumed] ->
      time = ms |> div(1000) |> LocalDay.local_time(zone) |> Calendar.strftime("%H:%M")
      %{id: "hour-#{ms}", time: time, produced: produced, consumed: consumed}
    end)
  end

  @spec energy_summary(map) :: String.t()
  def energy_summary(energy) do
    produced = Enum.sum(energy.produced_kwh)
    consumed = energy.consumers |> Enum.flat_map(& &1.kwh) |> Enum.sum()

    "Energie der letzten 24 Stunden: #{number(produced, precision: 2, unit: "kWh")} erzeugt, " <>
      "#{number(consumed, precision: 2, unit: "kWh")} an den Steckdosen verbraucht."
  end

  @spec power_summary(map, Roster.t()) :: String.t()
  def power_summary(%{series: series}, roster) do
    producer_ids = Roster.producer_ids(roster)
    {producers, consumers} = Enum.split_with(series, &(&1.plug_id in producer_ids))

    "Leistung der letzten 24 Stunden: höchstens #{number(peak(producers), unit: "W")} erzeugt, " <>
      "höchstens #{number(peak(consumers), unit: "W")} verbraucht."
  end

  defp peak(series) do
    series
    |> Enum.flat_map(& &1.points)
    |> Enum.reject(&is_nil(List.last(&1)))
    |> Enum.group_by(&hd/1, &List.last/1)
    |> Enum.map(fn {_ts, watts} -> Enum.sum(watts) end)
    |> Enum.max(fn -> nil end)
  end

  @spec history(Config.t(), Date.t()) :: %{points: [map] | nil}
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

  @spec history_rows([map]) :: [map]
  def history_rows(points) do
    for %{date: iso, energy_wh: wh} <- points do
      %{id: "day-#{iso}", day: iso |> Date.from_iso8601!() |> day_month(), kwh: wh / 1000}
    end
  end

  @spec history_summary([map]) :: String.t()
  def history_summary(points) do
    total = points |> Enum.map(& &1.energy_wh) |> Enum.sum()
    best = Enum.max_by(points, & &1.energy_wh)
    best_day = best.date |> Date.from_iso8601!() |> day_month()

    "Ertrag der letzten #{@history_days} Tage: #{number(total / 1000, precision: 2, unit: "kWh")}, " <>
      "am meisten am #{best_day} mit #{number(best.energy_wh / 1000, precision: 2, unit: "kWh")}."
  end
end
