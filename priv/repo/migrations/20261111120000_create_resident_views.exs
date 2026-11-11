defmodule Ziwoas.Repo.Migrations.CreateResidentViews do
  use Ecto.Migration

  def change do
    create table(:favourites) do
      add :resident, :string, null: false
      add :kind, :string, null: false
      add :device_id, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:favourites, [:resident, :kind, :device_id])

    create table(:default_views) do
      add :resident, :string, null: false
      add :view, :string, null: false
      add :room_id, references(:rooms, on_delete: :delete_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:default_views, [:resident])
    create index(:default_views, [:room_id])
  end
end
