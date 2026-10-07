defmodule Ziwoas.Plugs.Aggregator do
  @moduledoc """
  Folds a finished local day of raw `samples` into `samples_5min` and
  `daily_totals` (and the day's energy summary when plugs are given, through
  `Ziwoas.Energy.summarize_day/3`), purges raw samples past their retention
  and backs the database up. The arithmetic stays in SQLite.
  `Ziwoas.Plugs.AggregatorJob` runs it every night through `Ziwoas.Plugs.aggregate/3`.
  """
  import Ecto.Query

  alias Ziwoas.{Energy, LocalDay, Repo}
  alias Ziwoas.Plugs.{DailyTotal, EnergyDeltas, Sample, Sample5min}

  @raw_retention_days 7
  @bucket_seconds 300

  def raw_retention_days, do: @raw_retention_days

  @doc "Rewrites one local day; running it twice gives the same rows. `plugs` nil skips the summary."
  @spec aggregate_day(Date.t(), String.t(), list | nil) :: :ok
  def aggregate_day(%Date{} = date, timezone, plugs) do
    {start_ts, end_ts} = LocalDay.window(date, timezone)
    deltas = EnergyDeltas.query(start_ts, end_ts)

    {:ok, :ok} =
      Repo.transaction(fn ->
        Repo.delete_all(
          from s in Sample5min, where: s.bucket_ts >= ^start_ts and s.bucket_ts < ^end_ts
        )

        Repo.delete_all(from d in DailyTotal, where: d.date == ^date)
        Repo.insert_all(Sample5min, five_minute_means(deltas))
        Repo.insert_all(DailyTotal, daily_totals(deltas, date))

        if plugs, do: Energy.summarize_day(plugs, timezone, date)
        :ok
      end)

    :ok
  end

  defp five_minute_means(deltas) do
    bucketed =
      from d in subquery(deltas),
        select: %{
          plug_id: d.plug_id,
          bucket_ts: fragment("(? / ?) * ?", d.ts, ^@bucket_seconds, ^@bucket_seconds),
          apower_w: d.apower_w,
          delta_wh: d.delta_wh
        }

    from b in subquery(bucketed),
      group_by: [b.plug_id, b.bucket_ts],
      select: %{
        plug_id: b.plug_id,
        bucket_ts: b.bucket_ts,
        avg_power_w: avg(b.apower_w),
        energy_delta_wh: sum(b.delta_wh),
        sample_count: count()
      }
  end

  defp daily_totals(deltas, date) do
    from d in subquery(deltas),
      group_by: d.plug_id,
      select: %{plug_id: d.plug_id, date: type(^date, :date), energy_wh: sum(d.delta_wh)}
  end

  @doc "Drops raw samples older than the retention; a sample exactly at the cutoff stays."
  @spec purge_old_raw(integer, non_neg_integer) :: non_neg_integer
  def purge_old_raw(now_unix, retention_days \\ @raw_retention_days) do
    cutoff = now_unix - retention_days * 86_400
    {count, _} = Repo.delete_all(from s in Sample, where: s.ts < ^cutoff)
    count
  end

  @doc """
  Aggregates every finished day not yet in `daily_totals`, from the UTC date of
  the oldest sample up to the day before `:today`, then purges. Without
  samples it does nothing.

  Options: `:today` (default: today in `timezone`) and `:now` (Unix seconds),
  both from `Ziwoas.Clock`.
  """
  @spec run(String.t(), list | nil, keyword) :: :ok
  def run(timezone, plugs, opts \\ []) do
    today = Keyword.get_lazy(opts, :today, fn -> Ziwoas.Clock.today(timezone) end)
    now = Keyword.get_lazy(opts, :now, &Ziwoas.Clock.unix_now/0)

    case Repo.one(from s in Sample, select: min(s.ts)) do
      nil ->
        :ok

      min_ts ->
        existing = MapSet.new(Repo.all(from d in DailyTotal, distinct: true, select: d.date))
        earliest = min_ts |> DateTime.from_unix!() |> DateTime.to_date()

        for date <- Date.range(earliest, Date.add(today, -1), 1),
            date not in existing,
            do: aggregate_day(date, timezone, plugs)

        purge_old_raw(now)
        :ok
    end
  end

  @doc """
  Copies the database the process writes to into `dir/ziwoas-<today>.db`
  (`VACUUM INTO`, replacing that day's file) and keeps the newest `keep`
  backups by modification time. `VACUUM INTO` cannot run inside a transaction.
  """
  @spec backup!(String.t(), Date.t(), pos_integer) :: String.t()
  def backup!(dir, %Date{} = today, keep \\ 7) do
    File.mkdir_p!(dir)
    filename = Path.join(dir, "ziwoas-#{Date.to_iso8601(today)}.db")
    File.rm(filename)
    Repo.query!("VACUUM INTO ?", [filename])
    prune_backups(dir, keep)
    filename
  end

  defp prune_backups(dir, keep) do
    dir
    |> Path.join("ziwoas-*.db")
    |> Path.wildcard()
    |> Enum.sort_by(&File.stat!(&1, time: :posix).mtime)
    |> Enum.drop(-keep)
    |> Enum.each(&File.rm!/1)
  end
end
