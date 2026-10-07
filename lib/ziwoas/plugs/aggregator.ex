defmodule Ziwoas.Plugs.Aggregator do
  @moduledoc """
  Folds a finished local day of raw `samples` into `samples_5min` and
  `daily_totals` (and `daily_energy_summary` when plugs are given), then purges
  raw samples past their retention. All arithmetic stays in SQLite.

  Writes need a writable repo: `Ziwoas.Plugs.AggregatorJob` wraps it in
  `Ziwoas.Repo.write(:aggregator, fun)` (main or shadow database by ownership
  mode).
  """
  import Ecto.Query

  alias Ziwoas.{LocalDay, PowerSeries, Repo}
  alias Ziwoas.EnergyReport.{DailyEnergySummary, DailyEnergySummaryBuilder}
  alias Ziwoas.Plugs.{DailyTotal, EnergyDeltas, Sample, Sample5min}

  @default_raw_retention_days 7

  @enforce_keys [:timezone]
  defstruct timezone: nil, raw_retention_days: @default_raw_retention_days, plugs: nil

  @type t :: %__MODULE__{
          timezone: String.t(),
          raw_retention_days: non_neg_integer,
          plugs: list | nil
        }

  def default_raw_retention_days, do: @default_raw_retention_days

  @spec new(keyword) :: t
  def new(opts), do: struct!(__MODULE__, opts)

  @doc "Rewrites one local day; running it twice gives the same rows."
  @spec aggregate_day(t, Date.t()) :: :ok
  def aggregate_day(%__MODULE__{} = aggregator, %Date{} = date) do
    date_s = Date.to_iso8601(date)
    {start_ts, end_ts} = LocalDay.window(date, aggregator.timezone)

    {:ok, :ok} =
      Repo.transaction(fn ->
        Repo.delete_all(
          from s in Sample5min, where: s.bucket_ts >= ^start_ts and s.bucket_ts <= ^(end_ts - 1)
        )

        Repo.delete_all(from d in DailyTotal, where: d.date == ^date_s)

        Repo.query!(EnergyDeltas.cte() <> insert_5min_sql(), [start_ts, end_ts])
        Repo.query!(EnergyDeltas.cte() <> insert_daily_sql(), [start_ts, end_ts, date_s])

        if aggregator.plugs, do: write_summary(aggregator, date)
        :ok
      end)

    :ok
  end

  defp insert_5min_sql do
    """
    INSERT INTO samples_5min (plug_id, bucket_ts, avg_power_w, energy_delta_wh, sample_count)
    SELECT plug_id,
           #{PowerSeries.bucket_ts_sql(PowerSeries.sample_5min_bucket_seconds())} AS bucket_ts,
           AVG(apower_w) AS avg_power_w,
           SUM(delta_wh) AS energy_delta_wh,
           COUNT(*) AS sample_count
      FROM deltas
     GROUP BY plug_id, bucket_ts
    """
  end

  defp insert_daily_sql do
    """
    INSERT INTO daily_totals (plug_id, date, energy_wh)
    SELECT plug_id, ?, SUM(delta_wh) AS energy_wh
      FROM deltas
     GROUP BY plug_id
    """
  end

  defp write_summary(aggregator, date) do
    date_s = Date.to_iso8601(date)
    Repo.delete_all(from s in DailyEnergySummary, where: s.date == ^date_s)
    summary = DailyEnergySummaryBuilder.build(aggregator.plugs, aggregator.timezone, date)

    Repo.insert!(%DailyEnergySummary{
      date: date_s,
      produced_wh: :erlang.float(summary.produced_wh),
      consumed_wh: :erlang.float(summary.consumed_wh),
      self_consumed_wh: :erlang.float(summary.self_consumed_wh)
    })
  end

  @doc "Drops raw samples older than the retention; a sample exactly at the cutoff stays."
  @spec purge_old_raw(t, integer) :: non_neg_integer
  def purge_old_raw(%__MODULE__{} = aggregator, now \\ Ziwoas.Clock.unix_now()) do
    cutoff = now - aggregator.raw_retention_days * 86_400
    {count, _} = Repo.delete_all(from s in Sample, where: s.ts < ^cutoff)
    count
  end

  @doc """
  Copies the database the process writes to into `dir/ziwoas-<today>.db`
  (`VACUUM INTO`, replacing that day's file) and keeps the newest `keep`
  backups by modification time. A file outside the database, so only as the
  `:aggregator` owner: a shadow run would overwrite Rails' backup of the day.
  """
  @spec backup!(String.t(), Date.t(), pos_integer) :: String.t()
  def backup!(dir, %Date{} = today, keep \\ 7) do
    Ziwoas.Ownership.ensure_owner!(:aggregator)
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

  @doc """
  Aggregates every finished day not yet in `daily_totals`, from the UTC date of
  the oldest sample up to yesterday, then purges. Without samples it does nothing.

  Options: `:today` (default: today in the aggregator's zone, as Rails' `Date.today`
  under the container's `TZ`) and `:now` (Unix seconds), both from `Ziwoas.Clock`.
  """
  @spec run_once(t, keyword) :: :ok
  def run_once(%__MODULE__{} = aggregator, opts \\ []) do
    today = Keyword.get_lazy(opts, :today, fn -> Ziwoas.Clock.today(aggregator.timezone) end)
    now = Keyword.get_lazy(opts, :now, &Ziwoas.Clock.unix_now/0)

    case Repo.one(from s in Sample, select: min(s.ts)) do
      nil ->
        :ok

      min_ts ->
        existing = MapSet.new(Repo.all(from d in DailyTotal, select: d.date))
        earliest = min_ts |> DateTime.from_unix!() |> DateTime.to_date()

        for date <- Date.range(earliest, Date.add(today, -1), 1),
            Date.to_iso8601(date) not in existing,
            do: aggregate_day(aggregator, date)

        purge_old_raw(aggregator, now)
        :ok
    end
  end
end
