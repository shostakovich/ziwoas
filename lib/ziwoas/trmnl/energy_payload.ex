defmodule Ziwoas.Trmnl.EnergyPayload do
  @moduledoc """
  The TRMNL energy widget's `merge_variables`: today's balance plus 24 hours
  of production and consumption in 144 ten-minute buckets that end at the
  next local 10-minute boundary. Watts are whole and never negative, which
  keeps the payload under TRMNL's 2 kB.
  """
  alias Ziwoas.{Clock, Config, Energy, LocalDay, Plugs}
  alias Ziwoas.Energy.{Amount, PowerSeries}
  alias Ziwoas.Plugs.Roster
  alias Ziwoas.Trmnl.Window

  @bucket_seconds 600
  @buckets 144

  @spec build(Config.t(), DateTime.t()) :: %{merge_variables: map}
  def build(%Config{} = config, now \\ Clock.now()) do
    zone = config.location.timezone
    balance = Energy.today(config, now)
    {start_ts, end_ts} = window(now, zone)
    {pv_w, cons_w} = power_series(config, start_ts, end_ts)
    plug_ids = config |> Config.plug_roster() |> Roster.ids()
    ts = Plugs.latest_sample_ts(plug_ids, start_ts, end_ts) || DateTime.to_unix(now)

    %{
      merge_variables: %{
        ts: ts,
        stand: clock_label(ts, zone),
        pv_kwh: rounded_kwh(balance.produced),
        cons_kwh: rounded_kwh(balance.consumed),
        bilanz_kwh: rounded_kwh(Amount.subtract(balance.produced, balance.consumed)),
        autarky: percent(Energy.autarky_ratio(balance)),
        self_use: percent(Energy.self_consumption_ratio(balance)),
        pv_w: pv_w,
        cons_w: cons_w
      }
    }
  end

  @doc "`{start_ts, end_ts}`: 24 hours up to the local 10-minute boundary after `now`."
  @spec window(DateTime.t(), String.t()) :: {integer, integer}
  def window(now, zone), do: Window.ending_after(now, zone, @bucket_seconds, @buckets)

  defp power_series(config, start_ts, end_ts) do
    empty = List.duplicate(0.0, @buckets)

    {pv, cons} =
      config.plugs
      |> Energy.power_series(start_ts, end_ts, @bucket_seconds)
      |> PowerSeries.buckets()
      |> Enum.reduce({empty, empty}, fn bucket, {pv, cons} ->
        idx = Integer.floor_div(bucket.ts - start_ts, @bucket_seconds)

        if idx < 0 or idx >= @buckets,
          do: {pv, cons},
          else:
            {List.update_at(pv, idx, &(&1 + bucket.production_w)),
             List.update_at(cons, idx, &(&1 + bucket.consumption_w))}
      end)

    {Enum.map(pv, &whole_watts/1), Enum.map(cons, &whole_watts/1)}
  end

  defp whole_watts(watts), do: max(round(watts), 0)

  defp clock_label(ts, zone), do: ts |> LocalDay.local_time(zone) |> Calendar.strftime("%H:%M")

  # + 0.0 turns -0.0 into 0.0, which TRMNL would print as "-0,0".
  defp rounded_kwh(energy), do: Float.round(Amount.kwh(energy), 2) + 0.0

  defp percent(ratio), do: round(ratio * 100)
end
