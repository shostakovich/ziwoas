defmodule Ziwoas.Repo.Migrations.NormalizeRailsDrift do
  @moduledoc """
  Where the production database drifted from `db/schema.rb`: its index on
  `samples.ts` is named `idx_samples_ts` (schema.rb: `index_samples_on_ts`). The
  baseline adds the schema's index, this drops the drifted twin.

  Other drift is left as it is because neither a column's affinity nor its constraints
  differ: some string columns are declared `varchar(255)` instead of `varchar`, and
  `daily_energy_summary` names its primary key as a table constraint.
  """
  use Ecto.Migration

  def up do
    drop_if_exists index(:samples, [:ts], name: :idx_samples_ts)
  end

  # The baseline's index_samples_on_ts stays; the duplicate is not restored.
  def down, do: :ok
end
