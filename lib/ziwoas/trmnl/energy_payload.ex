defmodule Ziwoas.Trmnl.EnergyPayload do
  @moduledoc """
  The TRMNL energy widget's `merge_variables` (Rails' `TrmnlPayloadBuilder`):
  today's balance plus 24 hours of production and consumption in 144
  ten-minute buckets that end at the next local 10-minute boundary.

  The result is an ordered pair list for `Ziwoas.RubyJSON`; the push job
  itself is still Rails'.
  """
  import Ecto.Query

  alias Ziwoas.{Clock, Config, Energy, EnergySummary, LocalDay, PowerSeries, Repo, RubyNumeric}
  alias Ziwoas.Plugs.Sample

  @bucket_seconds 600
  @buckets 144

  @spec build(Config.t(), DateTime.t()) :: [{String.t(), term}]
  def build(%Config{} = config, now \\ Clock.now()) do
    zone = config.location.timezone
    summary = EnergySummary.compute_today(config, now)
    {start_ts, end_ts} = window(now, zone)
    {pv_w, cons_w} = power_series(config, start_ts, end_ts)
    ts = sample_ts(config, start_ts, end_ts, now)

    [
      {"merge_variables",
       [
         {"ts", ts},
         {"stand", clock_label(ts, zone)},
         {"pv_kwh", rounded_kwh(summary.produced)},
         {"cons_kwh", rounded_kwh(summary.consumed)},
         {"bilanz_kwh", rounded_kwh(Energy.subtract(summary.produced, summary.consumed))},
         {"autarky", percent(EnergySummary.autarky_ratio(summary))},
         {"self_use", percent(EnergySummary.self_consumption_ratio(summary))},
         {"pv_w", pv_w},
         {"cons_w", cons_w}
       ]}
    ]
  end

  @doc "`{start_ts, end_ts}`: 24 hours up to the 10-minute boundary after `now`, local time."
  @spec window(DateTime.t(), String.t()) :: {integer, integer}
  def window(now, zone) do
    local = DateTime.shift_zone!(now, zone)

    slot = %{
      DateTime.to_naive(local)
      | minute: div(local.minute, 10) * 10,
        second: 0,
        microsecond: {0, 0}
    }

    end_ts = DateTime.to_unix(LocalDay.to_instant(slot, zone)) + @bucket_seconds
    {end_ts - @buckets * @bucket_seconds, end_ts}
  end

  defp power_series(config, start_ts, end_ts) do
    empty = List.duplicate(0.0, @buckets)

    {pv, cons} =
      config.plugs
      |> PowerSeries.from_samples(start_ts, end_ts, @bucket_seconds)
      |> PowerSeries.buckets()
      |> Enum.reduce({empty, empty}, fn bucket, {pv, cons} ->
        idx = Integer.floor_div(bucket.ts - start_ts, @bucket_seconds)

        if idx < 0 or idx >= @buckets,
          do: {pv, cons},
          else:
            {List.update_at(pv, idx, &(&1 + bucket.production_w)),
             List.update_at(cons, idx, &(&1 + bucket.consumption_w))}
      end)

    {Enum.map(pv, &RubyNumeric.round(&1, 0)), Enum.map(cons, &RubyNumeric.round(&1, 0))}
  end

  defp sample_ts(%Config{plugs: []}, _start_ts, _end_ts, now), do: DateTime.to_unix(now)

  defp sample_ts(config, start_ts, end_ts, now) do
    ids = Enum.map(config.plugs, & &1.id)

    Repo.one(
      from s in Sample,
        where: s.plug_id in ^ids and s.ts >= ^start_ts and s.ts < ^end_ts,
        select: max(s.ts)
    ) || DateTime.to_unix(now)
  end

  defp clock_label(ts, zone), do: ts |> LocalDay.local_time(zone) |> Calendar.strftime("%H:%M")

  defp rounded_kwh(energy), do: energy |> Energy.kwh() |> RubyNumeric.round(2)

  defp percent(ratio), do: RubyNumeric.round(ratio * 100, 0)
end
