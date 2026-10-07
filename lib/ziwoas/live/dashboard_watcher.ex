defmodule Ziwoas.Live.DashboardWatcher do
  @moduledoc """
  Bridge for the dashboard's live updates while Rails' collector still writes
  `samples` (issue #158, until Phase 4). Rails' `ShellyStatusHandler` calls
  `DashboardBroadcaster.broadcast_live(deltas:)` at most every 5 s, and
  `DashboardSummaryJob` calls `broadcast_summary` every minute. Here:

    * every `:interval_ms` (default 5 s, Rails' `BROADCAST_INTERVAL`) the
      newest sample's rowid is polled; when it moved, `{:dashboard_live,
      deltas}` goes out on the `dashboard` topic. `deltas` are the
      `LiveState::Update`s of the plugs that reported since, as JSON-ready
      pair lists (newest sample, and the signed mean of its minute bucket).
      Without a subscriber on this node the deltas are not queried, only the
      rowid moves on;
    * every `:summary_interval_ms` (default 60 s) `{:dashboard_summary}`.

  With `live: false` (Phoenix owns `plug_ingest`, whose handler broadcasts the
  deltas itself) only the summary beat remains.

  Options: `:interval_ms`, `:summary_interval_ms`, `:live` (default true), `:name`.
  """
  use GenServer

  require Logger

  alias Ziwoas.{Config, Repo, RubyNumeric}
  alias Ziwoas.Plugs.Roster

  @topic "dashboard"
  @default_interval_ms 5_000
  @default_summary_interval_ms 60_000
  @bucket_s 60

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    summary_interval = Keyword.get(opts, :summary_interval_ms, @default_summary_interval_ms)
    Process.send_after(self(), :summary, summary_interval)

    # :unknown until a read succeeds; that first rowid is the baseline, not news.
    # (nil is an empty table: its first sample is news.)
    state = %{
      interval: Keyword.get(opts, :interval_ms, @default_interval_ms),
      summary_interval: summary_interval,
      last_rowid: nil
    }

    if Keyword.get(opts, :live, true),
      do: {:ok, schedule(%{state | last_rowid: with(:error <- newest_rowid(), do: :unknown)})},
      else: {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state =
      case newest_rowid() do
        :error ->
          state

        rowid when rowid == state.last_rowid ->
          state

        rowid when state.last_rowid == :unknown ->
          %{state | last_rowid: rowid}

        rowid ->
          if subscribed?(), do: broadcast(state.last_rowid)
          %{state | last_rowid: rowid}
      end

    {:noreply, schedule(state)}
  end

  def handle_info(:summary, state) do
    Phoenix.PubSub.broadcast(Ziwoas.PubSub, @topic, {:dashboard_summary})
    Process.send_after(self(), :summary, state.summary_interval)
    {:noreply, state}
  end

  defp schedule(state) do
    Process.send_after(self(), :poll, state.interval)
    state
  end

  # Phoenix.PubSub registers local subscribers in a Registry named after it; the
  # dashboard runs on one node.
  defp subscribed?, do: Registry.count_match(Ziwoas.PubSub, @topic, :_) > 0

  defp broadcast(since_rowid) do
    deltas = deltas(Config.plug_roster(Config.app_config()), since_rowid)
    Phoenix.PubSub.broadcast(Ziwoas.PubSub, @topic, {:dashboard_live, deltas})
  rescue
    error -> Logger.warning("DashboardWatcher: #{Exception.message(error)}")
  end

  # A busy or missing database is no reason to crash the bridge; try again next time.
  defp newest_rowid do
    %{rows: [[rowid]]} = Repo.query!("SELECT MAX(rowid) FROM samples")
    rowid
  rescue
    error ->
      Logger.warning("DashboardWatcher: #{Exception.message(error)}")
      :error
  end

  @doc """
  The `LiveState::Update` of every configured plug with a sample after
  `since_rowid` (nil: any), in roster order: its newest sample and the mean
  of that sample's minute bucket, signed like the 24 h chart (producers
  positive), and the plug's last known output.
  """
  @spec deltas(Roster.t(), integer | nil) :: [[{String.t(), term}]]
  def deltas(%Roster{} = roster, since_rowid) do
    %{rows: rows} =
      Repo.query!(
        # +plug_id: grouping by the bare column would scan the whole (plug_id, ts) index
        # instead of seeking the rowid range.
        "SELECT plug_id, MAX(ts) FROM samples WHERE rowid > ? GROUP BY +plug_id",
        [since_rowid || 0]
      )

    latest = Map.new(rows, fn [plug_id, ts] -> {plug_id, ts} end)

    for plug <- roster.all, ts = latest[plug.id], not is_nil(ts) do
      bucket_ts = div(ts, @bucket_s) * @bucket_s
      watts = bucket_watts(plug.id, bucket_ts, ts)
      avg = Enum.reduce(watts, 0.0, &(&2 + &1)) / length(watts)

      [
        {"id", plug.id},
        {"name", plug.name},
        {"role", plug.role},
        {"apower_w", List.last(watts)},
        {"last_seen_ts", ts},
        {"bucket_ts", bucket_ts},
        {"avg_power_w", Roster.signed_watts(roster, plug.id, avg)},
        {"output", output(plug.id)}
      ]
    end
  end

  # The bucket's samples up to the newest, oldest first: Rails sums them as they arrive.
  defp bucket_watts(plug_id, bucket_ts, ts) do
    %{rows: rows} =
      Repo.query!(
        "SELECT apower_w FROM samples WHERE plug_id = ? AND ts >= ? AND ts <= ? ORDER BY ts",
        [plug_id, bucket_ts, ts]
      )

    Enum.map(rows, fn [watts] -> RubyNumeric.to_f(watts) end)
  end

  defp output(plug_id) do
    case Repo.query!("SELECT output FROM plug_states WHERE plug_id = ? LIMIT 1", [plug_id]) do
      %{rows: [[output]]} when output in [0, 1] -> output == 1
      _ -> nil
    end
  end
end
