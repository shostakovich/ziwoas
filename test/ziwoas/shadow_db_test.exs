defmodule Ziwoas.ShadowDbTest do
  use ExUnit.Case, async: true

  alias Exqlite.Sqlite3
  alias Ziwoas.ShadowDb

  @moduletag :tmp_dir

  defp tables(path) do
    {:ok, conn} = Sqlite3.open(path, mode: :readonly)

    {:ok, st} =
      Sqlite3.prepare(conn, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")

    {:ok, rows} = Sqlite3.fetch_all(conn, st)
    Sqlite3.close(conn)
    List.flatten(rows)
  end

  describe "the shadow is never the main database" do
    setup %{tmp_dir: dir} do
      main = Path.join(dir, "main.sqlite3")
      File.write!(main, "")
      %{main: main}
    end

    test "the same path, spelt differently, is refused", %{tmp_dir: dir, main: main} do
      assert_raise RuntimeError, ~r/is the main database/, fn ->
        ShadowDb.check_distinct!(Path.join([dir, "x", "..", "main.sqlite3"]), main)
      end
    end

    test "a symlink to the main file or to its directory is refused", %{tmp_dir: dir, main: main} do
      File.ln_s!(main, Path.join(dir, "shadow.sqlite3"))
      File.ln_s!(dir, Path.join(dir, "alias"))
      File.ln_s!("alias/main.sqlite3", Path.join(dir, "relative.sqlite3"))

      for shadow <- ["shadow.sqlite3", "alias/main.sqlite3", "relative.sqlite3"] do
        assert_raise RuntimeError, ~r/is the main database/, fn ->
          ShadowDb.check_distinct!(Path.join(dir, shadow), main)
        end
      end
    end

    test "a hard link is refused", %{tmp_dir: dir, main: main} do
      File.ln!(main, Path.join(dir, "hard.sqlite3"))

      assert_raise RuntimeError, fn ->
        ShadowDb.check_distinct!(Path.join(dir, "hard.sqlite3"), main)
      end
    end

    test "another file, existing or not, passes", %{tmp_dir: dir, main: main} do
      File.write!(Path.join(dir, "other.sqlite3"), "")

      assert ShadowDb.check_distinct!(Path.join(dir, "other.sqlite3"), main) == :ok
      assert ShadowDb.check_distinct!(Path.join(dir, "missing/shadow.sqlite3"), main) == :ok
    end

    test "a symlink loop does not hang", %{tmp_dir: dir, main: main} do
      File.ln_s!(Path.join(dir, "loop_b"), Path.join(dir, "loop_a"))
      File.ln_s!(Path.join(dir, "loop_a"), Path.join(dir, "loop_b"))

      assert ShadowDb.check_distinct!(Path.join(dir, "loop_a"), main) == :ok
    end

    test "the writers refuse it at boot", %{tmp_dir: dir, main: main} do
      File.ln_s!(main, Path.join(dir, "shadow.sqlite3"))
      owners = %{Ziwoas.Ownership.all_rails() | weather: :shadow}

      assert_raise RuntimeError, ~r/is the main database/, fn ->
        Ziwoas.Repo.writer_children(owners, Path.join(dir, "shadow.sqlite3"), main)
      end
    end
  end

  test "a missing file gets the Rails schema", %{tmp_dir: dir} do
    path = Path.join(dir, "nested/shadow.sqlite3")

    assert ShadowDb.prepare!(path) == path
    assert "samples" in tables(path)
    assert "weather_records" in tables(path)
    refute "schema_migrations" in tables(path)
  end

  test "an existing shadow keeps its rows", %{tmp_dir: dir} do
    path = ShadowDb.prepare!(Path.join(dir, "shadow.sqlite3"))
    {:ok, conn} = Sqlite3.open(path)
    :ok = Sqlite3.execute(conn, "INSERT INTO samples VALUES (1.0, 2.0, 'bkw', 3)")
    Sqlite3.close(conn)

    ShadowDb.prepare!(path)

    {:ok, conn} = Sqlite3.open(path)
    {:ok, st} = Sqlite3.prepare(conn, "SELECT count(*) FROM samples")
    assert {:ok, [[1]]} = Sqlite3.fetch_all(conn, st)
    Sqlite3.close(conn)
  end

  test "a file with another schema is refused", %{tmp_dir: dir} do
    path = Path.join(dir, "old.sqlite3")
    {:ok, conn} = Sqlite3.open(path)
    :ok = Sqlite3.execute(conn, "CREATE TABLE samples (ts integer)")
    Sqlite3.close(conn)

    assert_raise RuntimeError, ~r/does not have the current Rails schema/, fn ->
      ShadowDb.prepare!(path)
    end
  end

  test "the statements are the fixture's DDL" do
    statements = ShadowDb.statements()

    assert Enum.all?(statements, &String.starts_with?(&1, "CREATE "))
    assert Enum.count(statements, &String.starts_with?(&1, "CREATE TABLE")) == 19
  end
end
