defmodule Ziwoas.Plugs.EnergyDeltas do
  @moduledoc """
  Shared CTE for plausibility-capped energy deltas from cumulative counters.

  Emits `WITH window_samples AS (...), deltas AS (...)` over `samples`, exposing
  per-row `delta_wh` (plus plug_id/ts/apower_w). Callers append their own
  SELECT and bind `params/3`. It stays SQL on SQLite on purpose: integer
  division, the Integer 0 of a dropped delta and SUM's compensation are
  SQLite's, exactly as Rails gets them.
  """

  # 20 kW is above any realistic single-circuit load, while counter glitches
  # can imply megawatts for a few seconds.
  @max_plausible_w 20_000

  def max_plausible_w, do: @max_plausible_w

  @doc "With `plug_ids`, the window is limited to those plugs (an empty list matches none)."
  @spec cte([String.t()] | nil) :: String.t()
  def cte(plug_ids \\ nil) do
    """
    WITH window_samples AS (
      SELECT plug_id, ts, apower_w, aenergy_wh,
             LAG(ts)         OVER (PARTITION BY plug_id ORDER BY ts) AS prev_ts,
             LAG(aenergy_wh) OVER (PARTITION BY plug_id ORDER BY ts) AS prev_wh
        FROM samples
       WHERE #{plug_filter(plug_ids)} ts >= ? AND ts < ?
    ),
    deltas AS (
      SELECT plug_id, ts, apower_w,
             CASE
               WHEN prev_wh IS NULL      THEN 0
               WHEN aenergy_wh < prev_wh THEN 0
               WHEN aenergy_wh - prev_wh
                    > #{@max_plausible_w}.0 * (ts - prev_ts) / 3600.0 THEN 0
               ELSE aenergy_wh - prev_wh
             END AS delta_wh
        FROM window_samples
    )
    """
  end

  @doc "Bind values for `cte/1`, in placeholder order."
  @spec params([String.t()] | nil, integer, integer) :: list
  def params(plug_ids \\ nil, start_ts, end_ts), do: List.wrap(plug_ids) ++ [start_ts, end_ts]

  @doc "`IN (?, ?)` for a list of binds; `IN (NULL)` for none, as Rails expands an empty array."
  @spec placeholders([term]) :: String.t()
  def placeholders([]), do: "NULL"
  def placeholders(values), do: Enum.map_join(values, ", ", fn _ -> "?" end)

  defp plug_filter(nil), do: ""
  defp plug_filter(plug_ids), do: "plug_id IN (#{placeholders(plug_ids)}) AND"
end
