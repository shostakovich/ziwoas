defmodule Ziwoas.Plugs.EnergyDeltas do
  @moduledoc """
  Plausibility-capped energy deltas from the cumulative counters in `samples`,
  as a query: one row per sample in the window with `plug_id`, `ts`,
  `apower_w` and `delta_wh`, for callers to aggregate further.

  A delta is dropped (0) for a plug's first sample in the window, when the
  counter went backwards (a reset), and when it implies more than
  `max_plausible_w/0` over the gap since the previous sample (a glitch).
  """
  import Ecto.Query

  alias Ziwoas.Plugs.Sample

  # 20 kW is above any realistic single-circuit load, while counter glitches
  # can imply megawatts for a few seconds.
  @max_plausible_w 20_000

  def max_plausible_w, do: @max_plausible_w

  @doc "Samples in `[start_ts, end_ts)`; with `plug_ids`, only those plugs (an empty list matches none)."
  @spec query(integer, integer, [String.t()] | nil) :: Ecto.Query.t()
  def query(start_ts, end_ts, plug_ids \\ nil) do
    window_samples =
      from(s in Sample,
        where: s.ts >= ^start_ts and s.ts < ^end_ts,
        windows: [by_plug: [partition_by: s.plug_id, order_by: s.ts]],
        select: %{
          plug_id: s.plug_id,
          ts: s.ts,
          apower_w: s.apower_w,
          aenergy_wh: s.aenergy_wh,
          prev_ts: over(lag(s.ts), :by_plug),
          prev_wh: over(lag(s.aenergy_wh), :by_plug)
        }
      )
      |> only_plugs(plug_ids)

    max_w = @max_plausible_w * 1.0

    from w in subquery(window_samples),
      select: %{
        plug_id: w.plug_id,
        ts: w.ts,
        apower_w: w.apower_w,
        delta_wh:
          fragment(
            """
            CASE
              WHEN ? IS NULL THEN 0
              WHEN ? < ? THEN 0
              WHEN ? - ? > ? * (? - ?) / 3600.0 THEN 0
              ELSE ? - ?
            END
            """,
            w.prev_wh,
            w.aenergy_wh,
            w.prev_wh,
            w.aenergy_wh,
            w.prev_wh,
            ^max_w,
            w.ts,
            w.prev_ts,
            w.aenergy_wh,
            w.prev_wh
          )
      }
  end

  defp only_plugs(query, nil), do: query
  defp only_plugs(query, plug_ids), do: where(query, [s], s.plug_id in ^plug_ids)
end
