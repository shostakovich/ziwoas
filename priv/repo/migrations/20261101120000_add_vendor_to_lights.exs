defmodule Ziwoas.Repo.Migrations.AddVendorToLights do
  use Ecto.Migration

  def change do
    alter table(:lights) do
      add :vendor, :string, null: false, default: "govee"
    end
  end
end
