defmodule Ziwoas.SchemaParityTest do
  # Lives as long as the Rails adoption (Ziwoas.Release) and its fixture
  # test/fixtures/rails_schema.sql, i.e. until after the cutover. A database
  # the migrations build from nothing must have the schema Rails generated, so a fresh
  # install behaves like the production database Phoenix adopts. That holds up to the
  # migrations that follow the adoption: from UtcDatetimeUsecTimestamps on, both
  # databases take the same changes. Works on files of its own, outside the SQL sandbox.
  use ExUnit.Case, async: true

  alias Exqlite.Sqlite3
  alias Ziwoas.{RailsDatabase, TestMigrations}

  @moduletag :tmp_dir

  # migration_leases belongs to the port branch, not to the production schema.
  @not_compared ~w(migration_leases schema_migrations sqlite_sequence)

  # The last migration before the schema moves away from Rails' (UtcDatetimeUsecTimestamps).
  @rails_schema_version 20_261_006_130_000

  # Type names that differ while SQLite derives the same affinity from them.
  @aliases %{"varchar" => "text", "float" => "real", "bigint" => "integer"}

  test "a freshly migrated database has the schema Rails generated", %{tmp_dir: dir} do
    rails = schema(RailsDatabase.build!(Path.join(dir, "rails.sqlite3")))

    fresh_path = Path.join(dir, "fresh.sqlite3")
    TestMigrations.run!(RailsDatabase.start_repo!(fresh_path), to: @rails_schema_version)
    fresh = schema(fresh_path)

    assert Map.keys(fresh) == Map.keys(rails)
    assert map_size(rails) == 18

    for {table, expected} <- rails do
      assert {table, fresh[table]} == {table, expected}
    end
  end

  defp schema(path) do
    {:ok, conn} = Sqlite3.open(path, mode: :readonly)

    try do
      for [name, sql] <- rows(conn, "SELECT name, sql FROM sqlite_master WHERE type = 'table'"),
          name not in @not_compared,
          into: %{} do
        {name,
         %{
           columns: columns(conn, name),
           indexes: indexes(conn, name),
           autoincrement: sql =~ "AUTOINCREMENT"
         }}
      end
    after
      Sqlite3.close(conn)
    end
  end

  defp columns(conn, table) do
    for [_cid, name, type, not_null, default, pk] <-
          rows(conn, "SELECT * FROM pragma_table_info(?)", [table]),
        into: %{} do
      {name,
       %{
         type: Map.get(@aliases, String.downcase(type), String.downcase(type)),
         affinity: affinity(type),
         not_null: not_null == 1,
         # FALSE and false are the same keyword.
         default: default && String.downcase(default),
         pk: pk
       }}
    end
  end

  defp indexes(conn, table) do
    for [_seq, name, unique, origin, partial] <-
          rows(conn, "SELECT * FROM pragma_index_list(?)", [table]),
        into: %{} do
      columns = rows(conn, "SELECT name FROM pragma_index_info(?) ORDER BY seqno", [name])

      {name,
       %{
         unique: unique == 1,
         origin: origin,
         columns: List.flatten(columns),
         where: partial == 1 && where_clause(conn, name)
       }}
    end
  end

  defp where_clause(conn, index) do
    [[sql]] = rows(conn, "SELECT sql FROM sqlite_master WHERE name = ?", [index])
    [_, where] = Regex.run(~r/\bWHERE\s+(.+)$/is, sql)
    String.trim(where)
  end

  # https://sqlite.org/datatype3.html#determination_of_column_affinity
  defp affinity(type) do
    type = String.upcase(type)

    cond do
      type =~ "INT" -> :integer
      type =~ ~r/CHAR|CLOB|TEXT/ -> :text
      type == "" or type =~ "BLOB" -> :blob
      type =~ ~r/REAL|FLOA|DOUB/ -> :real
      true -> :numeric
    end
  end

  defp rows(conn, sql, params \\ []) do
    {:ok, statement} = Sqlite3.prepare(conn, sql)

    try do
      :ok = Sqlite3.bind(statement, params)
      {:ok, rows} = Sqlite3.fetch_all(conn, statement)
      rows
    after
      Sqlite3.release(conn, statement)
    end
  end
end
