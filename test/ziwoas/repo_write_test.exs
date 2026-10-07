defmodule Ziwoas.RepoWriteTest do
  # The writers' registered names are global.
  use ExUnit.Case, async: false

  alias Ziwoas.{Ownership, Repo}
  alias Ziwoas.Ownership.NotOwnerError
  alias Ziwoas.Plugs.Sample

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    on_exit(&Ownership.clear_override/0)
    main = Ziwoas.RailsFixture.build!(Path.join(dir, "main.sqlite3"), rows: false)
    %{main: main, shadow: Path.join(dir, "shadow.sqlite3")}
  end

  defp start_repo!(opts),
    do: start_supervised!({Repo, [name: nil, pool_size: 1] ++ opts}, id: make_ref())

  defp sample(ts), do: %Sample{plug_id: "bkw", ts: ts, apower_w: 1.0, aenergy_wh: 2.0}

  defp count(repo) do
    previous = Repo.get_dynamic_repo()
    Repo.put_dynamic_repo(repo)

    try do
      Repo.aggregate(Sample, :count)
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp writers!(ctx) do
    main = start_repo!(database: ctx.main, writable: true)
    shadow = start_repo!(database: Ziwoas.ShadowDb.prepare!(ctx.shadow), writable: true)
    Repo.put_writer(:main, main)
    Repo.put_writer(:shadow, shadow)
    {main, shadow}
  end

  describe "a writer waits for Rails' write lock" do
    # Rails holds the write lock for `hold_ms` while the writer's transaction reads, then writes.
    defp against_rails_writer(repo, path, hold_ms) do
      {:ok, rails} = Exqlite.Sqlite3.open(path)
      :ok = Exqlite.Sqlite3.execute(rails, "BEGIN IMMEDIATE")
      :ok = Exqlite.Sqlite3.execute(rails, "INSERT INTO samples VALUES (1.0, 2.0, 'rails', 1)")

      task =
        Task.async(fn ->
          Repo.put_dynamic_repo(repo)

          try do
            Repo.transaction(fn ->
              Repo.aggregate(Sample, :count)
              Repo.insert!(sample(2))
            end)
          rescue
            error in Exqlite.Error -> {:raised, error}
          end
        end)

      Process.sleep(hold_ms)
      :ok = Exqlite.Sqlite3.execute(rails, "COMMIT")
      Exqlite.Sqlite3.close(rails)
      Task.await(task, 20_000)
    end

    test "an immediate transaction (the writers' default) waits out the busy timeout", ctx do
      repo = start_repo!(database: ctx.main, writable: true)

      assert {:ok, %Sample{}} = against_rails_writer(repo, ctx.main, 300)
      assert count(repo) == 2
    end

    test "a deferred one would fail at its first write", ctx do
      repo = start_repo!(database: ctx.main, writable: true, default_transaction_mode: :deferred)

      assert {:raised, %Exqlite.Error{message: "Database busy"}} =
               against_rails_writer(repo, ctx.main, 300)

      assert count(repo) == 1
    end
  end

  test "a rails task writes nowhere", ctx do
    {main, shadow} = writers!(ctx)

    assert_raise NotOwnerError, fn ->
      Repo.write(:plug_ingest, fn -> Repo.insert!(sample(1)) end)
    end

    assert {count(main), count(shadow)} == {0, 0}
  end

  test "shadow and dry run write only the shadow database", ctx do
    {main, shadow} = writers!(ctx)
    Ownership.override(%{plug_ingest: :shadow, switching: :dry_run})

    Repo.write(:plug_ingest, fn -> Repo.insert!(sample(1)) end)
    Repo.write(:switching, fn -> Repo.insert!(sample(2)) end)

    assert {count(main), count(shadow)} == {0, 2}
  end

  test "the owner writes the main database", ctx do
    {main, shadow} = writers!(ctx)
    Ownership.override(%{plug_ingest: :phoenix})

    assert %Sample{ts: 1} = Repo.write(:plug_ingest, fn -> Repo.insert!(sample(1)) end)
    assert {count(main), count(shadow)} == {1, 0}
  end

  test "reads inside a write see the target database, the repo is restored after", ctx do
    {_main, shadow} = writers!(ctx)
    Ownership.override(%{plug_ingest: :shadow})
    before = Repo.get_dynamic_repo()

    assert Repo.write(:plug_ingest, fn ->
             Repo.insert!(sample(1))
             Repo.get_dynamic_repo() == shadow and Repo.aggregate(Sample, :count) == 1
           end)

    assert Repo.get_dynamic_repo() == before
    assert_raise RuntimeError, fn -> Repo.write(:plug_ingest, fn -> raise "boom" end) end
    assert Repo.get_dynamic_repo() == before
  end

  test "the read connection refuses writes", ctx do
    repo = start_repo!(database: ctx.main)
    Repo.put_dynamic_repo(repo)

    assert_raise Exqlite.Error, ~r/readonly/, fn -> Repo.insert!(sample(1)) end
  end

  test "only the writers the owners need are started" do
    assert Repo.writer_children(Ownership.all_rails(), nil) == []

    assert [%{id: Ziwoas.Repo.MainWriter}] =
             Repo.writer_children(%{Ownership.all_rails() | economics: :phoenix}, nil)

    assert_raise RuntimeError, ~r/ZIWOAS_SHADOW_DB is required/, fn ->
      Repo.writer_children(%{Ownership.all_rails() | switching: :dry_run}, nil)
    end
  end

  test "started writers take the registered names write/2 finds", ctx do
    owners = %{Ownership.all_rails() | weather: :shadow, economics: :phoenix}
    Ownership.override(owners)
    Application.put_env(:ziwoas, :inherit_dynamic_repo, false)
    on_exit(fn -> Application.put_env(:ziwoas, :inherit_dynamic_repo, true) end)

    children = Repo.writer_children(owners, ctx.shadow)
    assert Enum.map(children, & &1.id) == [Ziwoas.Repo.MainWriter, Ziwoas.Repo.ShadowWriter]
    Enum.each(children, &start_supervised!/1)

    Repo.write(:weather, fn -> Repo.insert!(sample(1)) end)

    assert count(Ziwoas.Repo.ShadowWriter) == 1
    # The test env points the main writer at the shared test database; only read it.
    assert is_integer(count(Ziwoas.Repo.MainWriter))
  end
end
