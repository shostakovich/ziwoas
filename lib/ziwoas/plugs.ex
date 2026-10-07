defmodule Ziwoas.Plugs do
  @moduledoc """
  The plugs: their samples and relay states, five-minute means and daily
  totals, each plug's newest measurement, the nightly aggregation and the
  live updates.

  `subscribe/0` delivers `{:live, deltas}`, at most every 5 s per ingesting
  process, with one `Ziwoas.Plugs.Ingest.delta()` per plug that reported since.
  `subscribe(:aggregated)` delivers `{:aggregated, date}` once the nightly
  aggregation of `date` is done.
  """
  import Ecto.Query

  alias Ziwoas.Plugs.{Aggregator, DailyTotal, EnergyDeltas, Measurement, Sample, Sample5min}
  alias Ziwoas.Plugs.State
  alias Ziwoas.Repo

  @topic inspect(__MODULE__)
  @aggregated_topic @topic <> ":aggregated"

  @spec subscribe() :: :ok | {:error, term}
  def subscribe, do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)

  @spec subscribe(:aggregated) :: :ok | {:error, term}
  def subscribe(:aggregated), do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @aggregated_topic)

  @doc "Sends the live deltas an ingesting process collected to the subscribers."
  @spec notify_live([map]) :: :ok
  def notify_live(deltas) do
    broadcast(:live, deltas)
    :ok
  end

  defp broadcast(:aggregated, date),
    do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, @aggregated_topic, {:aggregated, date})

  defp broadcast(event, payload),
    do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, @topic, {event, payload})

  # --- Ingest ----------------------------------------------------------------

  @doc "Stores one sample; `:duplicate` when the plug already has one at `ts`."
  @spec record_sample(String.t(), integer, float, float) :: :ok | :duplicate
  def record_sample(plug_id, ts, apower_w, aenergy_wh) do
    sample = %{plug_id: plug_id, ts: ts, apower_w: apower_w, aenergy_wh: aenergy_wh}

    case Repo.insert_all(Sample, [sample], on_conflict: :nothing) do
      {1, _} -> :ok
      {0, _} -> :duplicate
    end
  end

  @doc "Stores the plug's relay output; true when it changed."
  @spec record_output(String.t(), boolean) :: boolean
  def record_output(plug_id, output) when is_boolean(output) do
    case Repo.get_by(State, plug_id: plug_id) do
      nil ->
        Repo.insert!(%State{plug_id: plug_id, output: output})
        true

      %State{output: ^output} ->
        false

      state ->
        state |> Ecto.Changeset.change(output: output) |> Repo.update!()
        true
    end
  end

  @doc "The last known relay state of each listed plug that has one, by plug id."
  @spec states([String.t()]) :: %{String.t() => State.t()}
  def states(plug_ids) do
    from(s in State, where: s.plug_id in ^plug_ids)
    |> Repo.all()
    |> Map.new(&{&1.plug_id, &1})
  end

  # --- Measurements ----------------------------------------------------------

  @doc """
  One `Measurement` per plug id as of `now`: the newest sample's watts, offline
  once no sample arrived for `offline_after_s` (fractions of a second count).
  """
  @spec latest_measurements([String.t()], DateTime.t(), number) :: %{
          String.t() => Measurement.t()
        }
  def latest_measurements(
        plug_ids,
        %DateTime{} = now,
        offline_after_s \\ Measurement.offline_after_s()
      ) do
    samples = latest_samples(plug_ids)
    now_s = DateTime.to_unix(now, :microsecond) / 1_000_000

    Map.new(plug_ids, fn plug_id ->
      sample = samples[plug_id]
      last_seen_ts = sample && sample.ts

      {plug_id,
       %Measurement{
         plug_id: plug_id,
         watt: sample && sample.apower_w && sample.apower_w * 1.0,
         last_seen_ts: last_seen_ts,
         offline: is_nil(last_seen_ts) or now_s - last_seen_ts > offline_after_s
       }}
    end)
  end

  defp latest_samples([]), do: %{}

  defp latest_samples(plug_ids) do
    newest =
      from s in Sample,
        where: s.plug_id in ^plug_ids,
        group_by: s.plug_id,
        select: %{plug_id: s.plug_id, ts: max(s.ts)}

    from(s in Sample,
      join: n in subquery(newest),
      on: n.plug_id == s.plug_id and n.ts == s.ts,
      select: %{plug_id: s.plug_id, ts: s.ts, apower_w: s.apower_w}
    )
    |> Repo.all()
    |> Map.new(&{&1.plug_id, &1})
  end

  @doc "The newest sample's `ts` of these plugs in `[start_ts, end_ts)`, nil without one."
  @spec latest_sample_ts([String.t()], integer, integer) :: integer | nil
  def latest_sample_ts([], _start_ts, _end_ts), do: nil

  def latest_sample_ts(plug_ids, start_ts, end_ts) do
    Repo.one(
      from s in Sample,
        where: s.plug_id in ^plug_ids and s.ts >= ^start_ts and s.ts < ^end_ts,
        select: max(s.ts)
    )
  end

  # --- Energy and power from raw samples -----------------------------------

  @doc """
  The energy these plugs' counters advanced in `[start_ts, end_ts)`, in Wh and
  summed over the plugs; implausible steps count nothing (`EnergyDeltas`).
  """
  @spec energy_wh([String.t()], integer, integer) :: float
  def energy_wh([], _start_ts, _end_ts), do: 0.0

  def energy_wh(plug_ids, start_ts, end_ts) do
    query =
      from d in subquery(EnergyDeltas.query(start_ts, end_ts, plug_ids)), select: sum(d.delta_wh)

    (Repo.one(query) || 0) * 1.0
  end

  @doc """
  The mean watts of each plug per bucket of `bucket_seconds` in
  `[start_ts, end_ts)`, as `{plug_id, bucket_ts, watts}`; a bucket's `ts` is
  floored to the bucket width.
  """
  @spec mean_power([String.t()], integer, integer, pos_integer) :: [
          {String.t(), integer, float | nil}
        ]
  def mean_power([], _start_ts, _end_ts, _bucket_seconds), do: []

  def mean_power(plug_ids, start_ts, end_ts, bucket_seconds) when is_integer(bucket_seconds) do
    bucketed =
      from s in Sample,
        where: s.plug_id in ^plug_ids and s.ts >= ^start_ts and s.ts < ^end_ts,
        select: %{
          plug_id: s.plug_id,
          bucket_ts: fragment("(? / ?) * ?", s.ts, ^bucket_seconds, ^bucket_seconds),
          apower_w: s.apower_w
        }

    from(b in subquery(bucketed),
      group_by: [b.plug_id, b.bucket_ts],
      select: {b.plug_id, b.bucket_ts, avg(b.apower_w)}
    )
    |> Repo.all()
  end

  # --- Aggregates ------------------------------------------------------------

  @doc "The five-minute means in `[start_ts, end_ts)`, by time."
  @spec samples_5min(integer, integer) :: [Sample5min.t()]
  def samples_5min(start_ts, end_ts) do
    Repo.all(
      from s in Sample5min,
        where: s.bucket_ts >= ^start_ts and s.bucket_ts < ^end_ts,
        order_by: s.bucket_ts
    )
  end

  @doc """
  `{bucket_ts, energy_delta_wh}` of each five-minute mean of these plugs in
  `[from, to)`, in no particular order; no query without plugs.
  """
  @spec five_minute_energy([String.t()], DateTime.t(), DateTime.t()) :: [{integer, float}]
  def five_minute_energy([], _from, _to), do: []

  def five_minute_energy(plug_ids, %DateTime{} = from, %DateTime{} = to) do
    {from_ts, to_ts} = {DateTime.to_unix(from), DateTime.to_unix(to)}

    Repo.all(
      from s in Sample5min,
        where: s.plug_id in ^plug_ids and s.bucket_ts >= ^from_ts and s.bucket_ts < ^to_ts,
        select: {s.bucket_ts, s.energy_delta_wh}
    )
  end

  @doc "The daily totals from `first` to `last` (both included), by date; all plugs, or the given ones."
  @spec daily_totals(Date.t(), Date.t(), [String.t()] | nil) :: [DailyTotal.t()]
  def daily_totals(%Date{} = first, %Date{} = last, plug_ids \\ nil) do
    from(d in DailyTotal, where: d.date >= ^first and d.date <= ^last, order_by: d.date)
    |> where_plugs(plug_ids)
    |> Repo.all()
  end

  defp where_plugs(query, nil), do: query
  defp where_plugs(query, plug_ids), do: where(query, [d], d.plug_id in ^plug_ids)

  @doc "The first and the last day with daily totals, or nil before the first."
  @spec daily_total_range() :: Date.Range.t() | nil
  def daily_total_range do
    case Repo.one(from d in DailyTotal, select: {min(d.date), max(d.date)}) do
      {%Date{} = first, %Date{} = last} -> Date.range(first, last)
      _ -> nil
    end
  end

  @doc "Every day with daily totals, oldest first."
  @spec dates_with_daily_totals() :: [Date.t()]
  def dates_with_daily_totals,
    do: Repo.all(from d in DailyTotal, distinct: true, select: d.date, order_by: d.date)

  @doc """
  Aggregates every finished local day not yet in the daily totals and purges
  old raw samples (`Ziwoas.Plugs.Aggregator.run/3`), then tells the
  subscribers `{:aggregated, today}`.
  """
  @spec aggregate(String.t(), list, keyword) :: :ok
  def aggregate(timezone, plugs, opts \\ []) do
    today = Keyword.get_lazy(opts, :today, fn -> Ziwoas.Clock.today(timezone) end)
    :ok = Aggregator.run(timezone, plugs, Keyword.put(opts, :today, today))
    broadcast(:aggregated, today)
    :ok
  end

  @doc "A `VACUUM INTO` copy of the database (`Ziwoas.Plugs.Aggregator.backup!/3`)."
  @spec backup!(String.t(), Date.t(), pos_integer) :: String.t()
  defdelegate backup!(dir, today, keep \\ 7), to: Aggregator
end
