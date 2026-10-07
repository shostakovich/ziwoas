defmodule Ziwoas.Plugs.EnergyDeltas do
  @moduledoc false
  import Ecto.Query

  alias Ziwoas.Plugs.Sample

  # Above any realistic single-circuit load; counter glitches imply megawatts.
  @max_plausible_w 20_000

  def max_plausible_w, do: @max_plausible_w

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
