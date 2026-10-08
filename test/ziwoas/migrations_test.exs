defmodule Ziwoas.MigrationsTest do
  use ExUnit.Case, async: true

  alias Ziwoas.{Repo, TestMigrations}

  @moduletag :tmp_dir

  @tables 18
  @versions [
    20_260_916_090_000,
    20_261_006_120_000,
    20_261_006_130_000,
    20_261_006_140_000,
    20_261_008_120_000
  ]

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

  test "sensor readings hold the SEN66's quantities and a fractional humidity",
       %{tmp_dir: dir} do
    TestMigrations.run!(open!(Path.join(dir, "room_air.sqlite3")))

    columns =
      Repo.query!("SELECT name, type FROM pragma_table_info('sensor_readings')").rows
      |> Map.new(fn [name, type] -> {name, type} end)

    assert Map.take(columns, ~w(pm1_0 pm2_5 pm4_0 pm10 voc_index nox_index device_status)) ==
             %{
               "pm1_0" => "REAL",
               "pm2_5" => "REAL",
               "pm4_0" => "REAL",
               "pm10" => "REAL",
               "voc_index" => "INTEGER",
               "nox_index" => "INTEGER",
               "device_status" => "INTEGER"
             }

    Repo.query!("""
    INSERT INTO sensor_readings (device_id, taken_at, humidity, inserted_at, updated_at)
    VALUES ('X', '2026-10-08T12:00:00.000000Z', 48.2,
            '2026-10-08T12:00:00.000000Z', '2026-10-08T12:00:00.000000Z')
    """)

    assert Repo.query!("SELECT humidity, typeof(humidity) FROM sensor_readings").rows ==
             [[48.2, "real"]]
  end
end
