defmodule Ziwoas.EnergyReport.DailyEnergySummary do
  @moduledoc "Produced, consumed and self-consumed energy of one local day (`daily_energy_summary`)."
  use Ziwoas.Schema

  # ISO date as text ("YYYY-MM-DD") is the primary key.
  @primary_key {:date, :string, autogenerate: false}
  schema "daily_energy_summary" do
    field :consumed_wh, :float
    field :produced_wh, :float
    field :self_consumed_wh, :float
  end
end
