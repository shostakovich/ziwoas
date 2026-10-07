defmodule Ziwoas.ReleaseTest do
  # Each test works on files of its own, outside the SQL sandbox.
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Exqlite.Sqlite3
  alias Ziwoas.{RailsDatabase, Release, Repo, TestMigrations}

  @moduletag :tmp_dir

  @rails_tables 18
  @versions [20_260_916_090_000, 20_261_006_120_000, 20_261_006_130_000, 20_261_006_140_000]

  # Rails' schema with a few rows, plus what production has besides: Rails' bookkeeping
  # and the drifted name of the samples index. The schema comes from the port branch and
  # has its migration_leases.
  defp rails_database!(dir) do
    RailsDatabase.build!(Path.join(dir, "rails.sqlite3"), """
    INSERT INTO "samples" ("aenergy_wh", "apower_w", "plug_id", "ts")
      VALUES (1000.25, 1001.25, 'fridge', 1774746003);
    INSERT INTO "cost_items" ("id", "amount_eur", "created_at", "label", "spent_on", "updated_at")
      VALUES (1, 12.35, '2026-03-29 00:59:59', 'Panel', '2026-03-29', '2026-03-29 01:00:00.120034');
    INSERT INTO "migration_leases" ("task", "heartbeat_at", "holder")
      VALUES ('weather', '2026-03-29 01:00:00.120034', 'rails');
    CREATE TABLE "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
    INSERT INTO "schema_migrations" VALUES ('20260501000000'), ('20260916090000');
    CREATE TABLE "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar,
      "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
    INSERT INTO "ar_internal_metadata"
      VALUES ('environment', 'production', '2026-05-02 11:05:02.954694', '2026-05-02 11:05:02.954694');
    DROP INDEX "index_samples_on_ts";
    CREATE INDEX "idx_samples_ts" ON "samples" ("ts");
    """)
  end

  defp sqlite!(path, sql) do
    {:ok, conn} = Sqlite3.open(path)
    :ok = Sqlite3.execute(conn, sql)
    Sqlite3.close(conn)
  end

  defp open!(path) do
    repo = RailsDatabase.start_repo!(path)
    Repo.put_dynamic_repo(repo)
    repo
  end

  defp tables do
    Repo.query!("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").rows
    |> List.flatten()
  end

  defp table_sql do
    Repo.query!(
      "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name NOT IN " <>
        "('schema_migrations', 'ar_internal_metadata', 'sqlite_sequence') ORDER BY name"
    ).rows
  end

  defp row_counts do
    for table <- tables(), table not in ~w(schema_migrations ar_internal_metadata), into: %{} do
      {table, Repo.query!(~s|SELECT count(*) FROM "#{table}"|).rows}
    end
  end

  defp indexes(table) do
    Repo.query!("SELECT name FROM pragma_index_list(?) ORDER BY name", [table]).rows
    |> List.flatten()
  end

  test "adopts a Rails database: its tables and rows stay, the migrations take over",
       %{tmp_dir: dir} do
    repo = open!(rails_database!(dir))
    assert "migration_leases" in tables()
    sql = Enum.reject(table_sql(), &match?(["migration_leases", _], &1))
    counts = Map.delete(row_counts(), "migration_leases")

    assert Release.adopt_rails_database!(Repo) == :adopted
    refute "schema_migrations" in tables()
    refute "ar_internal_metadata" in tables()

    assert TestMigrations.run!(repo) == @versions

    assert Repo.query!("SELECT version FROM schema_migrations ORDER BY version").rows ==
             Enum.map(@versions, &[&1])

    refute "migration_leases" in tables()
    assert table_sql() == Enum.map(sql, fn [name, sql] -> [name, inserted_at(sql)] end)
    assert row_counts() == counts
    assert counts["samples"] == [[1]]
    assert indexes("samples") == ["index_samples_on_ts", "sqlite_autoindex_samples_1"]

    assert Repo.query!("SELECT inserted_at, updated_at FROM cost_items").rows ==
             [["2026-03-29T00:59:59.000000Z", "2026-03-29T01:00:00.120034Z"]]
  end

  defp inserted_at(sql), do: String.replace(sql, ~s("created_at"), ~s("inserted_at"))

  test "a second run changes nothing", %{tmp_dir: dir} do
    repo = open!(rails_database!(dir))
    Release.adopt_rails_database!(Repo)
    TestMigrations.run!(repo)
    sql = table_sql()

    assert Release.adopt_rails_database!(Repo) == :not_rails
    assert TestMigrations.run!(repo) == []
    assert table_sql() == sql
  end

  test "refuses a Rails database with a table missing, and keeps its bookkeeping",
       %{tmp_dir: dir} do
    path = rails_database!(dir)
    sqlite!(path, ~s(DROP TABLE "cost_items"; DROP TABLE "solakon_pv_hours"))
    open!(path)

    assert_raise RuntimeError, ~r/tables missing: cost_items, solakon_pv_hours/, fn ->
      Release.adopt_rails_database!(Repo)
    end

    assert "schema_migrations" in tables()
    assert "ar_internal_metadata" in tables()
  end

  test "refuses a Rails database short of the schema the baseline reproduces",
       %{tmp_dir: dir} do
    path = rails_database!(dir)
    sqlite!(path, ~s(DELETE FROM "schema_migrations" WHERE version = '20260916090000'))
    open!(path)

    assert_raise RuntimeError, ~r/lacks Rails migration 20260916090000/, fn ->
      Release.adopt_rails_database!(Repo)
    end

    assert "schema_migrations" in tables()
  end

  test "an empty file is not Rails'; the migrations build every table", %{tmp_dir: dir} do
    repo = open!(Path.join(dir, "empty.sqlite3"))

    assert Release.adopt_rails_database!(Repo) == :not_rails
    assert TestMigrations.run!(repo) == @versions
    assert length(tables() -- ~w(schema_migrations sqlite_sequence)) == @rails_tables
  end

  test "mix ziwoas.adopt leaves the configured database alone when Rails never had it" do
    Sandbox.unboxed_run(Repo, fn ->
      tables = Repo.query!("SELECT name FROM sqlite_master ORDER BY name").rows

      Mix.Tasks.Ziwoas.Adopt.run([])

      assert Repo.query!("SELECT name FROM sqlite_master ORDER BY name").rows == tables
    end)
  end
end
