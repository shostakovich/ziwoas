defmodule Ziwoas.Solakon.Control.LoadReader do
  @moduledoc """
  The load a tick regulates against (Rails' `Solakon::Control::LoadReader`): the
  consumer plugs' live sum — nil when none of them is online — and the guaranteed
  floor, the lowest five-minute consumption total of the last 24 hours from raw
  samples.

  The floor's window aggregation is too heavy for every tick, so it is memoized for
  an hour, in the calling process (Rails: `Rails.cache`). The monitor job runs in its
  scheduler runner, which lives as long as the app; a restart recomputes it.
  """
  alias Ziwoas.{PowerSeries, RubyNumeric}
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

  @doc "The consumer plugs' latest measurements summed; nil without any online one."
  @spec current_consumption_w(Roster.t(), DateTime.t(), number) :: float | nil
  def current_consumption_w(roster, now, offline_after_s \\ Measurement.offline_after_s()) do
    ids = Roster.consumer_ids(roster)
    # Rails subtracts Times: the age keeps its fraction of a second.
    now_s = DateTime.to_unix(now, :microsecond) / 1_000_000
    ids |> Measurement.for_plugs(now_s, offline_after_s) |> Measurement.total_w(ids)
  end

  @doc "The lowest five-minute consumption total of the last 24 hours, 0.0 without samples."
  @spec guaranteed_floor_w(Roster.t(), DateTime.t()) :: float
  def guaranteed_floor_w(roster, now) do
    now_i = DateTime.to_unix(now)

    roster
    |> Roster.consumers()
    |> PowerSeries.from_samples(
      now_i - @floor_window_s,
      now_i + 1,
      PowerSeries.sample_5min_bucket_seconds()
    )
    |> PowerSeries.buckets()
    |> Enum.map(& &1.consumption_w)
    |> case do
      [] -> 0.0
      totals -> RubyNumeric.min(totals)
    end
  end

  @doc "Seeds this process's memo, as a warm `Rails.cache` would hold it."
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
