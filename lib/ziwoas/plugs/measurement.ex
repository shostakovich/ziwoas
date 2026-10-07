defmodule Ziwoas.Plugs.Measurement do
  @moduledoc """
  A plug's latest measurement and whether it still describes the plug now.
  A plug is offline once no sample arrived for
  `offline_after_s`; an offline plug reports no watts, not zero.
  """
  alias Ziwoas.Repo

  @offline_after_s 120

  @enforce_keys [:plug_id, :watt, :last_seen_ts, :offline]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          plug_id: String.t(),
          watt: float | nil,
          last_seen_ts: integer | nil,
          offline: boolean
        }

  def offline_after_s, do: @offline_after_s

  @doc "One measurement per plug id, as of `now_unix` (whole seconds)."
  @spec for_plugs([String.t()], integer, integer) :: %{String.t() => t}
  def for_plugs(plug_ids, now_unix, offline_after_s \\ @offline_after_s) do
    samples = Map.new(latest_per_plug(plug_ids), &{&1.plug_id, &1})

    Map.new(plug_ids, fn plug_id ->
      sample = samples[plug_id]
      last_seen_ts = sample && sample.ts

      {plug_id,
       %__MODULE__{
         plug_id: plug_id,
         watt: sample && sample.apower_w,
         last_seen_ts: last_seen_ts,
         offline: is_nil(last_seen_ts) or now_unix - last_seen_ts > offline_after_s
       }}
    end)
  end

  @spec reported_watt(t) :: float | nil
  def reported_watt(%__MODULE__{offline: true}), do: nil
  def reported_watt(%__MODULE__{watt: watt}), do: watt

  @doc "The online plugs' watts summed; nil, not 0.0, when none of them is online."
  @spec total_w(%{String.t() => t}, [String.t()]) :: float | nil
  def total_w(measurements, plug_ids) do
    case for(id <- plug_ids, m = Map.fetch!(measurements, id), not m.offline, do: m.watt) do
      [] -> nil
      watts -> Enum.sum(watts)
    end
  end

  # The newest sample of every plug.
  defp latest_per_plug([]), do: []

  defp latest_per_plug(plug_ids) do
    marks = Enum.map_join(plug_ids, ", ", fn _ -> "?" end)

    %{rows: rows} =
      Repo.query!(
        "SELECT plug_id, ts, apower_w FROM samples WHERE plug_id IN (#{marks}) " <>
          "AND (plug_id, ts) IN (SELECT plug_id, MAX(ts) FROM samples " <>
          "WHERE plug_id IN (#{marks}) GROUP BY plug_id)",
        plug_ids ++ plug_ids
      )

    for [plug_id, ts, apower_w] <- rows,
        do: %{plug_id: plug_id, ts: ts, apower_w: apower_w && apower_w * 1.0}
  end
end
