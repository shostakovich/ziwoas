defmodule Ziwoas.Lease.Row do
  @moduledoc "A row of `migration_leases` (`Ziwoas.Lease`, Rails' `MigrationLease`)."
  use Ziwoas.Schema

  @primary_key {:task, :string, autogenerate: false}
  schema "migration_leases" do
    field :holder, :string
    field :heartbeat_at, Ziwoas.Ecto.RailsDateTime
  end
end
