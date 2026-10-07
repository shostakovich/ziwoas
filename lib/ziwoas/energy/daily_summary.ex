defmodule Ziwoas.Energy.DailySummary do
  @moduledoc "Produced, consumed and self-consumed energy of one local day (`daily_energy_summary`), dated as ISO text."
  use Ziwoas.Schema

  @primary_key {:date, :date, autogenerate: false}
  schema "daily_energy_summary" do
    field :consumed_wh, :float
    field :produced_wh, :float
    field :self_consumed_wh, :float
  end

  @type t :: %__MODULE__{}
end
