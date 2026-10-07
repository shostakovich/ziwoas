defmodule Ziwoas.Release do
  @moduledoc """
  Database tasks a release runs without Mix (`bin/migrate`), and the one-time takeover
  of the SQLite file the Rails app left behind.

  Rails kept its migration versions in `schema_migrations` too, as a single `version`
  column; Ecto's table of that name has `inserted_at` as well and would misread it.
  So before the migrator runs, `adopt_rails_database!/0` drops Rails' bookkeeping.
  The baseline migration then finds every table in place and leaves it untouched.
  """
  require Logger

  @app :ziwoas

  # The tables of db/schema.rb at its last version, the one the baseline reproduces.
  @rails_version "20260916090000"
  @rails_tables ~w(cost_items daily_energy_summary daily_totals electricity_prices
                   light_states lights plug_states samples samples_5min scheduler_states
                   sensor_readings solakon_control_states solakon_pv_hours solakon_readings
                   solakon_snapshots switch_commands switch_rules weather_records)

  # One connection is all the migrator needs on SQLite, and on an empty file a second
  # one would race the first to switch it to WAL ("database is locked" while connecting).
  @migrator_opts [pool_size: 1]

  # Looking at the schema is bookkeeping, unlogged like Ecto's own queries on
  # schema_migrations; dropping Rails' tables is logged.
  @probe [log: false]

  @doc "Adopts a Rails database if there is one, then runs every pending migration."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          fn repo ->
            adopt_rails_database!(repo)
            Ecto.Migrator.run(repo, :up, all: true)
          end,
          @migrator_opts
        )
    end

    :ok
  end

  @doc """
  Starts `Ziwoas.Repo` on its configured database and adopts what Rails left there:
  see `adopt_rails_database!/1`.
  """
  @spec adopt_rails_database!() :: :adopted | :not_rails
  def adopt_rails_database! do
    load_app()

    {:ok, outcome, _} =
      Ecto.Migrator.with_repo(Ziwoas.Repo, &adopt_rails_database!/1, @migrator_opts)

    outcome
  end

  @doc """
  Drops Rails' `schema_migrations` and `ar_internal_metadata` from the database `repo`
  (or the caller's dynamic repo for it) points at, in one transaction, after checking
  that Rails migrated it to the schema the baseline reproduces. Raises, changing
  nothing, if it did not.

  Returns `:not_rails` without touching anything when there is no Rails
  `schema_migrations`: an empty file, or one Ecto already migrated.
  """
  @spec adopt_rails_database!(Ecto.Repo.t()) :: :adopted | :not_rails
  def adopt_rails_database!(repo) do
    if rails_database?(repo) do
      check_rails_schema!(repo)

      repo.transaction(fn ->
        repo.query!("DROP TABLE schema_migrations")
        repo.query!("DROP TABLE IF EXISTS ar_internal_metadata")
      end)

      Logger.info(
        "Adopted the Rails database: dropped schema_migrations and ar_internal_metadata"
      )

      :adopted
    else
      :not_rails
    end
  end

  defp rails_database?(repo) do
    "schema_migrations" in tables(repo) and
      "inserted_at" not in columns(repo, "schema_migrations")
  end

  defp check_rails_schema!(repo) do
    case @rails_tables -- tables(repo) do
      [] ->
        :ok

      missing ->
        raise "not adopting the Rails database: tables missing: #{Enum.join(missing, ", ")}"
    end

    %{rows: rows} =
      repo.query!("SELECT 1 FROM schema_migrations WHERE version = ?", [@rails_version], @probe)

    if rows == [] do
      raise "not adopting the Rails database: it lacks Rails migration #{@rails_version}, " <>
              "migrate it with the last Rails release first"
    end
  end

  defp tables(repo) do
    %{rows: rows} = repo.query!("SELECT name FROM sqlite_master WHERE type = 'table'", [], @probe)
    List.flatten(rows)
  end

  defp columns(repo, table) do
    %{rows: rows} = repo.query!("SELECT name FROM pragma_table_info(?)", [table], @probe)
    List.flatten(rows)
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app, do: Application.ensure_loaded(@app)
end
