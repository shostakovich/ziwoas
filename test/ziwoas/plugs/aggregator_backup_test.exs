defmodule Ziwoas.Plugs.AggregatorBackupTest do
  # Aggregator.backup!/3. VACUUM INTO cannot run inside a
  # transaction, so this test takes a connection outside the SQL sandbox and only
  # reads the test database; the backups go to files of their own.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Exqlite.Sqlite3
  alias Ziwoas.Plugs.Aggregator
  alias Ziwoas.Repo

  @moduletag :tmp_dir

  defp backups(dir),
    do: dir |> Path.join("ziwoas-*.db") |> Path.wildcard() |> Enum.map(&Path.basename/1)

  defp tables(path) do
    {:ok, conn} = Sqlite3.open(path, mode: :readonly)

    try do
      {:ok, statement} =
        Sqlite3.prepare(conn, "SELECT name FROM sqlite_master WHERE type = 'table'")

      {:ok, rows} = Sqlite3.fetch_all(conn, statement)
      List.flatten(rows)
    after
      Sqlite3.close(conn)
    end
  end

  test "replaces the day's file and keeps the newest seven", %{tmp_dir: dir} do
    for day <- 1..9 do
      path = Path.join(dir, "ziwoas-2026-04-0#{day}.db")
      File.write!(path, "old")
      File.touch!(path, 1_775_000_000 + day * 86_400)
    end

    File.touch!(Path.join(dir, "ziwoas-2026-04-01.db"), 1_775_000_000 + 20 * 86_400)

    path = Sandbox.unboxed_run(Repo, fn -> Aggregator.backup!(dir, ~D[2026-04-05]) end)

    assert path == Path.join(dir, "ziwoas-2026-04-05.db")
    assert backups(dir) == Enum.map([1, 4, 5, 6, 7, 8, 9], &"ziwoas-2026-04-0#{&1}.db")
    assert "samples" in tables(path)
  end
end
