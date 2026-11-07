defmodule Ziwoas.Repo.Migrations.AddMinSocToSolakonControlStates do
  use Ecto.Migration

  def change do
    alter table(:solakon_control_states) do
      add :min_soc_pct, :integer, null: false, default: 10
    end
  end
end
