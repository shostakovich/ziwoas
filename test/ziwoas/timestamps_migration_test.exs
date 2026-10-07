defmodule Ziwoas.TimestampsMigrationTest do
  # UtcDatetimeUsecTimestamps on a database shaped like the one Rails left behind. Each
  # test works on a file of its own, outside the SQL sandbox.
  use ExUnit.Case, async: true

  alias Ziwoas.{RailsDatabase, Repo, TestMigrations}

  @moduletag :tmp_dir

  @before 20_261_006_130_000
  @version 20_261_006_140_000

  # Rails wrote microseconds only when they were non-zero; a column may be NULL; one
  # value is in the new form already.
  @rows """
  INSERT INTO "cost_items" ("id", "amount_eur", "created_at", "label", "spent_on", "updated_at")
    VALUES (1, 12.35, '2026-03-29 00:59:59', 'Panel', '2026-03-29', '2026-03-29 01:00:00.120034'),
           (2, 3.10, '2026-03-30 08:00:00.000001', 'Kabel', '2026-03-30', '2026-03-30 08:00:00');
  INSERT INTO "light_states" ("id", "light_key", "created_at", "updated_at", "last_seen_at")
    VALUES (1, 'desk', '2026-06-28 11:46:32.265545', '2026-10-05 12:47:29.035120', NULL),
           (2, 'tv', '2026-06-28 11:46:32', '2026-10-05 12:47:29', '2026-10-05 12:47:29.034721');
  INSERT INTO "solakon_pv_hours" ("id", "started_at", "pv_power_w", "reading_count")
    VALUES (1, '2026-06-20 08:00:00', 512.5, 120);
  INSERT INTO "sensor_readings" ("id", "device_id", "taken_at", "created_at", "updated_at")
    VALUES (1, 'living', '2026-05-12T14:42:03.729615Z', '2026-05-12 14:42:03.827384',
            '2026-05-12 14:42:03.827384');
  INSERT INTO "switch_commands" ("id", "plug_id", "action", "source", "created_at", "updated_at")
    VALUES (1, 'fridge', 'on', 'manual', '2026-06-12 17:37:29.717945', '2026-06-12 17:37:29.717945');
  INSERT INTO "weather_records" ("id", "kind", "timestamp", "lat", "lon", "daytime", "created_at", "updated_at")
    VALUES (1, 'historic', '2026-04-21 00:00:00', 52.52, 13.405, 'night',
            '2026-05-07 19:05:17.394782', '2026-05-07 19:05:17.394782');
  """

  defp rails_database!(dir, sql \\ "") do
    repo =
      RailsDatabase.start_repo!(
        RailsDatabase.build!(Path.join(dir, "rails.sqlite3"), @rows <> sql)
      )

    Repo.put_dynamic_repo(repo)
    TestMigrations.run!(repo, to: @before)
    repo
  end

  defp rows(table, columns) do
    Repo.query!(~s|SELECT #{Enum.join(columns, ", ")} FROM "#{table}" ORDER BY id|).rows
  end

  defp columns(table),
    do: List.flatten(Repo.query!("SELECT name FROM pragma_table_info(?)", [table]).rows)

  defp count(table), do: Repo.query!(~s|SELECT count(*) FROM "#{table}"|).rows

  defp snapshot do
    for table <- ~w(cost_items light_states solakon_pv_hours sensor_readings switch_commands
                    weather_records),
        into: %{} do
      {table, Repo.query!(~s|SELECT * FROM "#{table}" ORDER BY id|).rows}
    end
  end

  test "renames created_at and rewrites every timestamp into Phoenix's form", %{tmp_dir: dir} do
    repo = rails_database!(dir)
    counts = Map.new(~w(cost_items light_states weather_records), &{&1, count(&1)})

    assert TestMigrations.run!(repo) == [@version]

    assert rows("cost_items", ~w(inserted_at updated_at)) == [
             ["2026-03-29T00:59:59.000000Z", "2026-03-29T01:00:00.120034Z"],
             ["2026-03-30T08:00:00.000001Z", "2026-03-30T08:00:00.000000Z"]
           ]

    assert rows("light_states", ~w(inserted_at updated_at last_seen_at)) == [
             ["2026-06-28T11:46:32.265545Z", "2026-10-05T12:47:29.035120Z", nil],
             [
               "2026-06-28T11:46:32.000000Z",
               "2026-10-05T12:47:29.000000Z",
               "2026-10-05T12:47:29.034721Z"
             ]
           ]

    assert rows("solakon_pv_hours", ~w(started_at)) == [["2026-06-20T08:00:00.000000Z"]]

    assert rows("sensor_readings", ~w(taken_at inserted_at)) == [
             ["2026-05-12T14:42:03.729615Z", "2026-05-12T14:42:03.827384Z"]
           ]

    assert rows("weather_records", ~w(timestamp inserted_at updated_at)) == [
             [
               "2026-04-21T00:00:00.000000Z",
               "2026-05-07T19:05:17.394782Z",
               "2026-05-07T19:05:17.394782Z"
             ]
           ]

    assert Map.new(counts, fn {table, _} -> {table, count(table)} end) == counts

    for table <-
          ~w(cost_items light_states solakon_control_states switch_commands weather_records) do
      assert "inserted_at" in columns(table)
      refute "created_at" in columns(table)
    end

    assert Repo.query!("SELECT name FROM pragma_index_list('switch_commands')").rows ==
             [["switch_commands_plug_id_inserted_at_index"]]

    assert Repo.query!("SELECT name FROM pragma_index_info(?)", [
             "switch_commands_plug_id_inserted_at_index"
           ]).rows == [["plug_id"], ["inserted_at"]]
  end

  test "the rewritten values load into the schemas", %{tmp_dir: dir} do
    repo = rails_database!(dir)
    TestMigrations.run!(repo)

    assert %{inserted_at: ~U[2026-03-29 00:59:59.000000Z]} =
             Repo.get!(Ziwoas.Economics.CostItem, 1)

    assert %{started_at: ~U[2026-06-20 08:00:00.000000Z]} = Repo.get!(Ziwoas.Solakon.PvHour, 1)
  end

  test "a value in neither form aborts the migration and changes nothing", %{tmp_dir: dir} do
    repo =
      rails_database!(dir, """
      INSERT INTO "weather_records" ("id", "kind", "timestamp", "lat", "lon", "daytime", "created_at", "updated_at")
        VALUES (2, 'historic', '2026-04-21T01:00:00', 52.52, 13.405, 'night',
                '2026-05-07 19:05:17', '2026-05-07 19:05:17');
      """)

    before = snapshot()

    assert_raise Ecto.MigrationError,
                 ~r/weather_records\.timestamp holds "2026-04-21T01:00:00".*nothing was changed/,
                 fn -> TestMigrations.run!(repo) end

    assert snapshot() == before
    assert "created_at" in columns("cost_items")
    assert Repo.query!("SELECT max(version) FROM schema_migrations").rows == [[@before]]
  end
end
