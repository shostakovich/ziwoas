defmodule Ziwoas.MigrationsTest do
  use ExUnit.Case, async: true

  alias Ziwoas.{Repo, TestMigrations}

  @moduletag :tmp_dir

  @tables 18
  @versions [20_260_916_090_000, 20_261_006_120_000, 20_261_006_130_000, 20_261_006_140_000]

  defp open!(path) do
    repo =
      start_supervised!(
        {Repo, name: nil, database: path, pool: DBConnection.ConnectionPool, pool_size: 1},
        id: {Repo, path}
      )

    Repo.put_dynamic_repo(repo)
    repo
  end

  defp tables do
    Repo.query!("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name").rows
    |> List.flatten()
  end

  test "the migrations build every table on an empty file, a second run changes nothing",
       %{tmp_dir: dir} do
    repo = open!(Path.join(dir, "empty.sqlite3"))

    assert TestMigrations.run!(repo) == @versions
    assert length(tables() -- ~w(schema_migrations sqlite_sequence)) == @tables

    schema = Repo.query!("SELECT name, sql FROM sqlite_master ORDER BY name").rows
    assert TestMigrations.run!(repo) == []
    assert Repo.query!("SELECT name, sql FROM sqlite_master ORDER BY name").rows == schema
  end
end
