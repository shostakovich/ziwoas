defmodule Ziwoas.Energy.PowerSeries do
  @moduledoc """
  The average power of a set of plugs over a run of equal time buckets.
  Producers report with the opposite sign; the roster applies that convention
  once, so every reader sees production as a positive magnitude.

  A reading without a watt value counts as 0.0 W. `Ziwoas.Energy.power_series/4`
  builds one from raw samples.
  """
  alias Ziwoas.Plugs.Roster

  defmodule Bucket do
    @moduledoc "Role totals of one bucket, in watts."
    @enforce_keys [:ts, :production_w, :consumption_w]
    defstruct @enforce_keys

    @type t :: %__MODULE__{ts: integer, production_w: float, consumption_w: float}
  end

  @enforce_keys [:bucket_seconds, :buckets, :watts_by_plug]
  defstruct @enforce_keys

  @type reading :: {String.t(), integer, number | nil}
  @type t :: %__MODULE__{
          bucket_seconds: integer,
          buckets: [Bucket.t()],
          watts_by_plug: %{String.t() => %{integer => float}}
        }

  @sample_5min_bucket_seconds 300
  @seconds_per_hour 3600.0

  def sample_5min_bucket_seconds, do: @sample_5min_bucket_seconds

  @spec new([reading], Roster.t() | list, pos_integer) :: t
  def new(readings, plugs, bucket_seconds) when is_integer(bucket_seconds) do
    roster = Roster.new(plugs)
    readings = normalize(readings, roster)

    %__MODULE__{
      bucket_seconds: bucket_seconds,
      buckets: buckets(readings, roster),
      watts_by_plug: watts_by_plug(readings, roster)
    }
  end

  @doc "From five-minute means (anything with plug_id, bucket_ts and avg_power_w)."
  @spec from_5min([map], Roster.t() | list) :: t
  def from_5min(rows, plugs) do
    rows
    |> Enum.map(&{&1.plug_id, &1.bucket_ts, &1.avg_power_w})
    |> new(plugs, @sample_5min_bucket_seconds)
  end

  @spec buckets(t) :: [Bucket.t()]
  def buckets(%__MODULE__{buckets: buckets}), do: buckets

  @doc "Signed watts of one plug by bucket ts; empty for a plug without readings."
  @spec signed_watts_by_ts(t, String.t()) :: %{integer => float}
  def signed_watts_by_ts(%__MODULE__{watts_by_plug: by_plug}, plug_id),
    do: Map.get(by_plug, plug_id, %{})

  @doc """
  The energy the consumers drew straight from production: the per-bucket
  overlap of both, clamped to what the meters counted; 0.0 without buckets.
  """
  @spec self_consumed_wh(t, number, number) :: float
  def self_consumed_wh(%__MODULE__{} = series, produced_wh, consumed_wh),
    do: Enum.min([overlap_wh(series), produced_wh * 1.0, consumed_wh * 1.0])

  defp overlap_wh(%__MODULE__{buckets: buckets, bucket_seconds: bucket_seconds}) do
    bucket_hours = bucket_seconds / @seconds_per_hour

    Enum.reduce(buckets, 0.0, fn bucket, sum ->
      sum + min(bucket.production_w, bucket.consumption_w) * bucket_hours
    end)
  end

  defp normalize(readings, roster) do
    readings
    |> Enum.filter(fn {plug_id, _ts, _watt} -> Roster.measured?(roster, plug_id) end)
    |> Enum.map(fn {plug_id, ts, watt} -> {plug_id, ts, if(watt, do: watt * 1.0, else: 0.0)} end)
    |> Enum.sort_by(fn {_plug_id, ts, _watt} -> ts end)
  end

  defp buckets(readings, roster) do
    readings
    |> Enum.chunk_by(fn {_plug_id, ts, _watt} -> ts end)
    |> Enum.map(&bucket(&1, roster))
  end

  defp bucket([{_plug_id, ts, _watt} | _] = readings, roster) do
    empty = %Bucket{ts: ts, production_w: 0.0, consumption_w: 0.0}
    Enum.reduce(readings, empty, &add_reading(&1, &2, roster))
  end

  defp add_reading({plug_id, _ts, watt}, bucket, roster) do
    key = Roster.bucket_key(roster, plug_id)
    Map.update!(bucket, key, &(&1 + Roster.signed_watts(roster, plug_id, watt)))
  end

  defp watts_by_plug(readings, roster) do
    Enum.reduce(readings, %{}, fn {plug_id, ts, watt}, by_plug ->
      signed = Roster.signed_watts(roster, plug_id, watt)
      Map.update(by_plug, plug_id, %{ts => signed}, &Map.put(&1, ts, signed))
    end)
  end
end
