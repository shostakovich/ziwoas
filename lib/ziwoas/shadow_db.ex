defmodule Ziwoas.ShadowDb do
  @moduledoc """
  The shadow database (`ZIWOAS_SHADOW_DB`): where Phoenix writes for the tasks it
  runs in `:shadow` or `:dry_run` (`Ziwoas.Ownership`), to hold against Rails' rows.
  Its schema is Rails' own, `priv/rails_schema.sql` (dumped from the removed Rails
  app's `db/schema.rb`); Ecto still runs no migrations.

  `prepare!/1` creates a missing or empty file with that schema and refuses a file
  whose schema differs: after a Rails migration a shadow run starts over from a
  fresh file.
  """
  alias Exqlite.Sqlite3

  @doc "The DDL statements of the Rails schema, as `sqlite_master` stores them."
  @spec statements() :: [String.t()]
  def statements do
    Application.app_dir(:ziwoas, "priv/rails_schema.sql")
    |> File.read!()
    |> String.split(";\n", trim: true)
    |> Enum.map(&strip_comments/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Raises unless `shadow` and `main` are different files: compared by their real
  paths (every symlink resolved) and, when both exist, by device and inode (a hard
  link). A shadow run on the main database would write Rails' rows.
  """
  @spec check_distinct!(String.t(), String.t()) :: :ok
  def check_distinct!(shadow, main) do
    if real_path(shadow) == real_path(main) or same_file?(shadow, main) do
      raise "ZIWOAS_SHADOW_DB #{shadow} is the main database #{main}: " <>
              "shadow and dry_run tasks would write Rails' rows"
    end

    :ok
  end

  @doc "`path` absolute with every symlink resolved; components that do not exist stay as they are."
  @spec real_path(String.t()) :: String.t()
  def real_path(path) do
    [root | parts] = path |> Path.expand() |> Path.split()
    resolve(parts, root, 0)
  end

  @max_links 40

  defp resolve([], resolved, _links), do: resolved

  defp resolve([part | rest], resolved, links) do
    candidate = Path.join(resolved, part)

    case :file.read_link_all(candidate) do
      {:ok, target} when links < @max_links ->
        [root | parts] = target |> List.to_string() |> Path.expand(resolved) |> Path.split()
        resolve(parts ++ rest, root, links + 1)

      _ ->
        resolve(rest, candidate, links)
    end
  end

  defp same_file?(a, b) do
    with {:ok, %File.Stat{inode: inode, major_device: device}} <- File.stat(a),
         {:ok, %File.Stat{inode: ^inode, major_device: ^device}} <- File.stat(b) do
      true
    else
      _ -> false
    end
  end

  @doc "Makes `path` a database with the Rails schema; raises if it holds another one."
  @spec prepare!(String.t()) :: String.t()
  def prepare!(path) do
    File.mkdir_p!(Path.dirname(path))
    {:ok, conn} = Sqlite3.open(path)

    try do
      :ok = Sqlite3.execute(conn, "PRAGMA journal_mode = WAL")

      case existing(conn) do
        [] -> :ok = Sqlite3.execute(conn, Enum.map_join(statements(), &(&1 <> ";\n")))
        found -> check!(path, found)
      end
    after
      Sqlite3.close(conn)
    end

    path
  end

  defp existing(conn) do
    {:ok, statement} =
      Sqlite3.prepare(
        conn,
        "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'"
      )

    try do
      {:ok, rows} = Sqlite3.fetch_all(conn, statement)
      Enum.map(rows, fn [sql] -> sql end)
    after
      Sqlite3.release(conn, statement)
    end
  end

  defp check!(path, found) do
    if Enum.sort(found) != Enum.sort(statements()) do
      raise "shadow database #{path} does not have the current Rails schema " <>
              "(priv/rails_schema.sql); move it away to start a fresh shadow run"
    end
  end

  defp strip_comments(sql) do
    sql
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(&1, "--"))
    |> Enum.join("\n")
    |> String.trim()
  end
end
