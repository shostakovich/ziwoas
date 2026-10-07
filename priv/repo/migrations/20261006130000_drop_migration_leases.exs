defmodule Ziwoas.Repo.Migrations.DropMigrationLeases do
  @moduledoc """
  `migration_leases` held the owner leases while Rails and Phoenix shared the
  database. Only copies from the port branch have it; production never did.
  """
  use Ecto.Migration

  def up do
    drop_if_exists table(:migration_leases)
  end

  # Nothing reads the leases any more.
  def down, do: :ok
end
