defmodule Ziwoas.Plugs.Measurement do
  @moduledoc false
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
end
