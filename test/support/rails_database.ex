defmodule Ziwoas.RailsDatabase do
  @moduledoc """
  SQLite files shaped like the database the Rails app left behind, from the schema it
  generated last (`test/fixtures/rails_schema.sql`, frozen since). Goes through the raw
  driver, never the Repo. For the adoption test (`Ziwoas.ReleaseTest`) and the schema
  parity test.
  """
  alias Exqlite.Sqlite3

  @schema_sql Path.expand("../fixtures/rails_schema.sql", __DIR__)
  @external_resource @schema_sql

  @doc "Creates `path` with Rails' schema, then runs `sql` on it; returns `path`."
  @spec build!(Path.t(), String.t()) :: Path.t()
  def build!(path, sql \\ "") do
    {:ok, conn} = Sqlite3.open(path)

    try do
      # Rails switches every database it opens to WAL.
      :ok = Sqlite3.execute(conn, "PRAGMA journal_mode = WAL")
      :ok = Sqlite3.execute(conn, File.read!(@schema_sql))
      :ok = Sqlite3.execute(conn, sql)
    after
      Sqlite3.close(conn)
    end

    path
  end

  @doc """
  Starts a `Ziwoas.Repo` instance on the file at `path`, outside the SQL sandbox, under
  the test's supervisor.
  """
  @spec start_repo!(Path.t()) :: pid
  def start_repo!(path),
    do:
      ExUnit.Callbacks.start_supervised!(
        {Ziwoas.Repo, name: nil, database: path, pool: DBConnection.ConnectionPool, pool_size: 1},
        id: {Ziwoas.Repo, path}
      )
end
