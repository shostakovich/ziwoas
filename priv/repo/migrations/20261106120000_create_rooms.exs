defmodule Ziwoas.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms) do
      add :name, :string, null: false
      add :position, :integer, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:rooms, [:name])

    alter table(:lights) do
      add :room_id, references(:rooms, on_delete: :nilify_all)
    end

    alter table(:heaters) do
      add :room_id, references(:rooms, on_delete: :nilify_all)
    end

    create table(:plug_rooms) do
      add :plug_id, :string, null: false
      add :room_id, references(:rooms, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:plug_rooms, [:plug_id])
    create index(:plug_rooms, [:room_id])
    create index(:lights, [:room_id])
    create index(:heaters, [:room_id])
  end
end
