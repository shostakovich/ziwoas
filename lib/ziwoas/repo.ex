defmodule Ziwoas.Repo do
  @moduledoc """
  The SQLite database Rails owns (issue #158: the file is the contract).

  `Ziwoas.Repo` itself, the instance every read goes through, opens the main
  database with SQLite's `SQLITE_OPEN_READONLY` flag: a write fails inside SQLite
  with "attempt to write a readonly database". Writes go through `write/2`, which
  points the calling process at one of two writer instances of this module, chosen
  by the task's mode (`Ziwoas.Ownership.write_target/1`):

    * `Ziwoas.Repo.MainWriter` — the main database read-write, started only while
      some task is `:phoenix`;
    * `Ziwoas.Repo.ShadowWriter` — the shadow database (`ZIWOAS_SHADOW_DB`,
      `Ziwoas.ShadowDb`), started only while some task is `:shadow` or `:dry_run`.

  No instance ever creates the main database file (the `:writable` option opens
  read-write without `SQLITE_OPEN_CREATE`).
  """
  use Ecto.Repo,
    otp_app: :ziwoas,
    adapter: Ecto.Adapters.SQLite3

  alias Ziwoas.Ownership

  @writers %{main: Ziwoas.Repo.MainWriter, shadow: Ziwoas.Repo.ShadowWriter}
  @writer_key {__MODULE__, :writer}

  @doc """
  Runs `fun` with this process's repo pointed at the database `task` writes to, and
  returns its result. Reads inside `fun` see that database too: a task's unit of
  work lives in one world, the main database as owner, the shadow database in
  shadow or dry run. Raises `Ziwoas.Ownership.NotOwnerError` for a `:rails` task,
  and for an owned one whose lease Rails holds (`Ziwoas.Lease`).
  Processes `fun` starts do not inherit the repo; call `write/2` in them again.
  """
  @spec write(Ownership.task(), (-> result)) :: result when result: var
  def write(task, fun) when is_function(fun, 0) do
    target = Ownership.write_target(task)
    if target == :main, do: Ownership.ensure_lease!(task)
    repo = writer(target)
    previous = get_dynamic_repo()
    put_dynamic_repo(repo)

    try do
      fun.()
    after
      put_dynamic_repo(previous)
    end
  end

  @doc "The writer instance for `:main` or `:shadow` (a test's `put_writer/2` first)."
  @spec writer(:main | :shadow) :: atom | pid
  def writer(target), do: test_writer(target) || Map.fetch!(@writers, target)

  @doc """
  Test support (`config :ziwoas, inherit_dynamic_repo: true`): `write/2` in this
  process and the processes it starts (`test_lineage/0`) uses `repo` for `target`.
  """
  @spec put_writer(:main | :shadow, atom | pid) :: :ok
  def put_writer(target, repo) when is_map_key(@writers, target) do
    Process.put({@writer_key, target}, repo)
    :ok
  end

  @doc """
  Child specs of the writers `owners` need (`Ziwoas.Application`). `shadow_database`
  is the shadow file's path, required once a task runs in shadow or dry run, and never
  the main database (`Ziwoas.ShadowDb.check_distinct!/2`); it is prepared
  (`Ziwoas.ShadowDb.prepare!/1`) here, before the repo opens it.
  """
  @spec writer_children(Ownership.owners(), String.t() | nil, String.t()) ::
          [Supervisor.child_spec()]
  def writer_children(
        owners,
        shadow_database,
        main_database \\ Application.fetch_env!(:ziwoas, __MODULE__)[:database]
      ) do
    modes = Map.values(owners)

    main =
      if :phoenix in modes,
        do: [writer_spec(:main, writable: true)],
        else: []

    shadow =
      if Enum.any?(modes, &(&1 in [:shadow, :dry_run])) do
        unless shadow_database,
          do: raise("ZIWOAS_SHADOW_DB is required while a task runs in shadow or dry_run")

        Ziwoas.ShadowDb.check_distinct!(shadow_database, main_database)

        [
          writer_spec(:shadow,
            writable: true,
            database: Ziwoas.ShadowDb.prepare!(shadow_database)
          )
        ]
      else
        []
      end

    main ++ shadow
  end

  defp writer_spec(target, opts) do
    name = Map.fetch!(@writers, target)
    Supervisor.child_spec({__MODULE__, [name: name] ++ opts}, id: name)
  end

  @doc """
  Test support: the processes that started this one, nearest first — `$callers`
  (Tasks, LiveViews under test), then `$ancestors` (a `start_supervised` child).
  """
  @spec test_lineage() :: [pid]
  def test_lineage,
    do: Enum.filter(Process.get(:"$callers", []) ++ Process.get(:"$ancestors", []), &is_pid/1)

  defp test_writer(target) do
    if Application.get_env(:ziwoas, :inherit_dynamic_repo, false) do
      key = {@writer_key, target}

      Enum.find_value([self() | test_lineage()], fn
        pid when pid == self() ->
          Process.get(key)

        pid ->
          case Process.info(pid, :dictionary) do
            {:dictionary, dictionary} ->
              with {_key, repo} <- List.keyfind(dictionary, key, 0), do: repo

            nil ->
              nil
          end
      end)
    end
  end

  @doc """
  Test support (`config :ziwoas, inherit_dynamic_repo: true`): adopts the
  dynamic repo of the nearest process in `$callers` that has one, so a
  LiveView under `Phoenix.LiveViewTest.live/2` reads the writable database of
  the test that started it (`Ziwoas.DataCase`). A no-op otherwise.
  """
  @spec inherit_dynamic_repo() :: :ok
  def inherit_dynamic_repo do
    if Application.get_env(:ziwoas, :inherit_dynamic_repo, false) do
      repo =
        Enum.find_value(Process.get(:"$callers", []), fn pid ->
          case Process.info(pid, :dictionary) do
            {:dictionary, dictionary} ->
              with {_key, repo} <- List.keyfind(dictionary, {__MODULE__, :dynamic_repo}, 0),
                   do: repo

            nil ->
              nil
          end
        end)

      if repo, do: put_dynamic_repo(repo)
    end

    :ok
  end

  # A writer begins its transactions IMMEDIATE: a deferred one that reads first and
  # then writes cannot wait for Rails' write lock (SQLite answers SQLITE_BUSY at
  # once, the busy timeout never applies), an immediate one waits at BEGIN.
  @impl true
  def init(_type, config) do
    if Keyword.get(config, :writable, false) do
      {:ok,
       config
       |> Keyword.put(:mode, :readwrite)
       |> Keyword.put_new(:default_transaction_mode, :immediate)}
    else
      {:ok, Keyword.put(config, :mode, :readonly)}
    end
  end
end
