defmodule Ziwoas.Repo.Migrations.UtcDatetimeUsecTimestamps do
  @moduledoc """
  Moves the timestamps from Rails' conventions to Phoenix's: `created_at` becomes
  `inserted_at`, and every timestamp column holds the text `:utc_datetime_usec` writes
  (`2026-10-06T12:00:00.000000Z`) instead of Rails' `2026-10-06 12:00:00` or
  `2026-10-06 12:00:00.123456` (UTC, microseconds only when non-zero).

  SQL compares these columns as text, so a table must not mix the two forms. All of it
  runs in the migration's one transaction: every value is checked first, and a value in
  neither form aborts the migration before anything changes. Values already in the new
  form stay as they are.

  The declared types stay `DATETIME(6)`; SQLite cannot change a column's type in place,
  and the NUMERIC affinity it gives leaves these texts alone.
  """
  use Ecto.Migration

  # Every DATETIME column of the schema Rails handed over. Unix seconds (samples.ts,
  # samples_5min.bucket_ts) and plain dates (date, valid_from, spent_on) are not here.
  @columns [
    cost_items: ~w(created_at updated_at),
    electricity_prices: ~w(created_at updated_at),
    light_states: ~w(created_at updated_at last_seen_at),
    lights: ~w(created_at updated_at),
    plug_states: ~w(created_at updated_at),
    scheduler_states: ~w(created_at updated_at last_tick_at),
    sensor_readings: ~w(created_at updated_at taken_at),
    solakon_control_states: ~w(created_at updated_at last_decision_at),
    solakon_pv_hours: ~w(started_at),
    solakon_readings: ~w(created_at updated_at taken_at),
    solakon_snapshots: ~w(created_at updated_at taken_at),
    switch_commands: ~w(created_at updated_at),
    switch_rules: ~w(created_at updated_at),
    weather_records: ~w(created_at updated_at timestamp)
  ]

  @digits2 "[0-9][0-9]"
  @date "#{@digits2}#{@digits2}-#{@digits2}-#{@digits2}"
  @clock "#{@digits2}:#{@digits2}:#{@digits2}"
  @usec ".#{@digits2}#{@digits2}#{@digits2}"
  @rails_seconds "#{@date} #{@clock}"
  @rails_usec "#{@date} #{@clock}#{@usec}"
  @converted "#{@date}T#{@clock}#{@usec}Z"

  def up do
    check_values!()

    for {table, columns} <- @columns do
      execute(rewrite_sql(table, columns))

      if "created_at" in columns do
        rename table(table), :created_at, to: :inserted_at
      end
    end

    # The rename carried the index over to inserted_at; its name still says created_at.
    drop index(:switch_commands, [:plug_id, :inserted_at],
           name: :index_switch_commands_on_plug_id_and_created_at
         )

    create index(:switch_commands, [:plug_id, :inserted_at])
  end

  def down do
    raise Ecto.MigrationError,
          "the timestamps stay in Phoenix's form; Rails' cannot be told apart from it afterwards"
  end

  defp check_values! do
    for {table, columns} <- @columns, column <- columns do
      quoted = name(column)

      %{rows: rows} =
        repo().query!(
          "SELECT #{quoted} FROM #{name(table)} WHERE #{quoted} IS NOT NULL " <>
            "AND NOT (#{quoted} GLOB ? OR #{quoted} GLOB ? OR #{quoted} GLOB ?) LIMIT 1",
          [@rails_seconds, @rails_usec, @converted]
        )

      with [[value]] <- rows do
        raise Ecto.MigrationError,
              "#{table}.#{column} holds #{inspect(value)}, neither Rails' timestamp " <>
                "(YYYY-MM-DD HH:MM:SS[.ffffff]) nor Phoenix's; nothing was changed"
      end
    end
  end

  # One pass per table; a row is rewritten once, whichever of its columns change.
  defp rewrite_sql(table, columns) do
    columns = Enum.map(columns, &name/1)

    sets =
      Enum.map_join(columns, ", ", fn column ->
        "#{column} = CASE " <>
          "WHEN #{column} GLOB '#{@rails_seconds}' THEN replace(#{column}, ' ', 'T') || '.000000Z' " <>
          "WHEN #{column} GLOB '#{@rails_usec}' THEN replace(#{column}, ' ', 'T') || 'Z' " <>
          "ELSE #{column} END"
      end)

    rails_shaped = Enum.map_join(columns, " OR ", &"#{&1} GLOB '#{@date} *'")

    "UPDATE #{name(table)} SET #{sets} WHERE #{rails_shaped}"
  end

  defp name(identifier), do: ~s("#{identifier}")
end
