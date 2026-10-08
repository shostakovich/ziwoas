defmodule Ziwoas.Solakon.Control.LoadReader do
  @moduledoc false
  alias Ziwoas.{Energy, Plugs}
  alias Ziwoas.Energy.PowerSeries
  alias Ziwoas.Plugs.{Measurement, Roster}
  alias Ziwoas.Solakon.Control.Load

  @floor_window_s 24 * 60 * 60
  @floor_cache_ttl_s 60 * 60
  @floor_key {__MODULE__, :floor_w}

  @spec load_estimate(Roster.t(), DateTime.t(), keyword) :: Load.t()
  def load_estimate(roster, now, opts \\ []) do
    offline_after_s = Keyword.get(opts, :offline_after_s, Measurement.offline_after_s())
    Load.new(current_consumption_w(roster, now, offline_after_s), cached_floor_w(roster, now))
  end

  @spec current_consumption_w(Roster.t(), DateTime.t(), number) :: float | nil
  def current_consumption_w(roster, now, offline_after_s \\ Measurement.offline_after_s()) do
    ids = Roster.consumer_ids(roster)
    ids |> Plugs.latest_measurements(now, offline_after_s) |> Measurement.total_w(ids)
  end

  @spec guaranteed_floor_w(Roster.t(), DateTime.t()) :: float
  def guaranteed_floor_w(roster, now) do
    now_i = DateTime.to_unix(now)

    roster
    |> Roster.consumers()
    |> Energy.power_series(
      now_i - @floor_window_s,
      now_i + 1,
      PowerSeries.sample_5min_bucket_seconds()
    )
    |> PowerSeries.buckets()
    |> Enum.map(& &1.consumption_w)
    |> case do
      [] -> 0.0
      totals -> Enum.min(totals)
    end
  end

  @spec cache_floor(float, DateTime.t()) :: :ok
  def cache_floor(floor_w, now) do
    Process.put(@floor_key, {floor_w, DateTime.to_unix(now) + @floor_cache_ttl_s})
    :ok
  end

  defp cached_floor_w(roster, now) do
    case Process.get(@floor_key) do
      {floor_w, expires_at} when expires_at > 0 ->
        if DateTime.to_unix(now) < expires_at, do: floor_w, else: fresh_floor_w(roster, now)

      _ ->
        fresh_floor_w(roster, now)
    end
  end

  defp fresh_floor_w(roster, now) do
    floor_w = guaranteed_floor_w(roster, now)
    cache_floor(floor_w, now)
    floor_w
  end
end
