defmodule Ziwoas.Repo.Migrations.CreateHeating do
  use Ecto.Migration

  def change do
    create table(:heaters) do
      add :key, :string, null: false
      add :ain, :string, null: false
      add :name, :string, null: false
      add :heat_c, :real, null: false, default: 21.0
      add :written_mode, :string
      add :written_c, :real
      add :pressed_state, :string
      add :pressed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:heaters, [:key])

    create table(:heater_windows) do
      add :heater_key, :string, null: false
      add :on_minute, :integer, null: false
      add :off_minute, :integer, null: false
      add :days, :text, null: false
      add :enabled, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create index(:heater_windows, [:heater_key])
  end
end
