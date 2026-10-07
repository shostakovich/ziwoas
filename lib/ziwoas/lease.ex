defmodule Ziwoas.Lease do
  @moduledoc """
  The owner lease (`migration_leases`, Rails' `MigrationLease`): runtime protection
  against both apps acting for one task, should their `migration.owners` disagree
  (a side not restarted, a mistyped config).

  Whichever app acts for an ingest or effect task holds the task's lease: one row
  with the holder (`"rails"`/`"phoenix"`) and its last heartbeat. Taking or renewing
  it is one conditional UPSERT that succeeds only while nobody else holds the lease
  or the other holder's heartbeat is older than two intervals (60 s). Phoenix
  heartbeats every task it owns (`:phoenix`) every 30 s from this process; Rails
  takes its lease each time it acts (its jobs, its routes) and from the collector's
  heartbeat. `:shadow` and `:dry_run` never take a lease; `:route` tasks have none
  (the reverse proxy sends each form to one app).

  Before acting, Phoenix asks `held?/1` (the last heartbeat from here succeeded and
  is younger than two intervals): `Ziwoas.Ownership.ensure_owner!/1` and
  `Ziwoas.Repo.write/2` raise `Ziwoas.Ownership.NotOwnerError` without it, the
  scheduler skips the run, `ZiwoasWeb.Owned` answers 503. A refused heartbeat is
  logged as an error, every interval, until the other app lets go.

  Started by `Ziwoas.Application` when Phoenix owns a leased task; off in tests
  (`config :ziwoas, leases: false`), where `held?/1` is always true.
  """
  use GenServer

  require Logger

  alias Ziwoas.{Clock, Ownership, Repo}
  alias Ziwoas.Ecto.RailsDateTime

  @holder "phoenix"
  @interval_ms 30_000

  # Takes or renews the lease unless another holder's heartbeat is fresh; RETURNING
  # yields a row only when the row was written.
  @acquire """
  INSERT INTO migration_leases (task, holder, heartbeat_at) VALUES (?1, ?2, ?3)
  ON CONFLICT (task) DO UPDATE SET holder = excluded.holder, heartbeat_at = excluded.heartbeat_at
  WHERE migration_leases.holder = excluded.holder OR migration_leases.heartbeat_at < ?4
  RETURNING holder
  """

  @doc "Whether the task has a lease: ingest and effect tasks do, route tasks do not."
  @spec leased?(Ownership.task()) :: boolean
  def leased?(task), do: Keyword.fetch!(Ownership.tasks(), task) != :route

  @doc "The leased tasks Phoenix acts for under `owners`."
  @spec tasks(Ownership.owners()) :: [Ownership.task()]
  def tasks(owners),
    do:
      for({task, _class} <- Ownership.tasks(), leased?(task), owners[task] == :phoenix, do: task)

  @doc "Whether leases are enforced here (`config :ziwoas, leases: false` in tests)."
  @spec enabled?() :: boolean
  def enabled?, do: Application.get_env(:ziwoas, :leases, true)

  @doc """
  Whether Phoenix may act for `task` now: its last heartbeat took the lease and is
  younger than two intervals. Always true for a task without a lease or while leases
  are off.
  """
  @spec held?(Ownership.task()) :: boolean
  def held?(task) do
    not enabled?() or not leased?(task) or
      case lookup(task) do
        {:held, until} -> DateTime.before?(Clock.now(), until)
        _ -> false
      end
  end

  @doc "Who holds `task`'s lease as far as this process knows (for the error message)."
  @spec holder(Ownership.task()) :: String.t() | nil
  def holder(task) do
    case lookup(task) do
      {:held, _until} -> @holder
      {:refused, holder} -> holder
      nil -> nil
    end
  end

  defp lookup(task) do
    case :ets.whereis(__MODULE__) do
      :undefined ->
        nil

      table ->
        case :ets.lookup(table, task) do
          [{^task, state}] -> state
          [] -> nil
        end
    end
  end

  # --- The heartbeat ---------------------------------------------------------------

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Options: `:tasks` (the leased tasks Phoenix owns), `:interval_ms` (30 s); for
  tests `:clock` (0-arity, a UTC `DateTime`). Takes the leases before it returns,
  so the collector and the scheduler, started after it, find them held.
  """
  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    :ets.new(__MODULE__, [:named_table, :protected, read_concurrency: true])

    state = %{
      tasks: Keyword.fetch!(opts, :tasks),
      interval_ms: Keyword.get(opts, :interval_ms, @interval_ms),
      clock: Keyword.get(opts, :clock, &Clock.now/0)
    }

    {:ok, beat(state)}
  end

  @impl true
  def handle_info(:beat, state), do: {:noreply, beat(state)}
  def handle_info(_message, state), do: {:noreply, state}

  # A clean stop hands the leases back at once instead of after two intervals.
  @impl true
  def terminate(_reason, state) do
    with_writer(fn ->
      for task <- state.tasks,
          do:
            Repo.query(
              "DELETE FROM migration_leases WHERE task = ?1 AND holder = ?2",
              [Atom.to_string(task), @holder]
            )
    end)

    :ok
  rescue
    _ -> :ok
  end

  defp beat(state) do
    now = state.clock.()
    until = DateTime.add(now, 2 * state.interval_ms, :millisecond)

    with_writer(fn -> Enum.each(state.tasks, &heartbeat(&1, now, until, state.interval_ms)) end)
    Process.send_after(self(), :beat, state.interval_ms)
    state
  end

  defp heartbeat(task, now, until, interval_ms) do
    stale_before = DateTime.add(now, -2 * interval_ms, :millisecond)

    case Repo.query(@acquire, [Atom.to_string(task), @holder, stamp(now), stamp(stale_before)]) do
      {:ok, %{rows: [_ | _]}} ->
        :ets.insert(__MODULE__, {task, {:held, until}})

      {:ok, %{rows: []}} ->
        holder = refused(task)
        :ets.insert(__MODULE__, {task, {:refused, holder}})

      {:error, error} ->
        Logger.error("lease: heartbeat of #{task} failed: #{Exception.message(error)}")
    end
  end

  defp refused(task) do
    {:ok, %{rows: rows}} =
      Repo.query("SELECT holder, heartbeat_at FROM migration_leases WHERE task = ?1", [
        Atom.to_string(task)
      ])

    [[holder, heartbeat_at] | _] = rows ++ [[nil, nil]]

    Logger.error(
      "lease: #{holder} holds #{task} (heartbeat #{heartbeat_at}): Phoenix does not act for it; " <>
        "check migration.owners on both sides"
    )

    holder
  end

  defp stamp(instant) do
    {:ok, text} = RailsDateTime.dump(instant)
    text
  end

  defp with_writer(fun) do
    previous = Repo.get_dynamic_repo()
    Repo.put_dynamic_repo(Repo.writer(:main))

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end
end
