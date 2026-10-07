defmodule Ziwoas.Economics.ElectricityPrice do
  @moduledoc "Price per kWh valid from a date on (`electricity_prices`)."
  use Ziwoas.Schema

  @type t :: %__MODULE__{}

  schema "electricity_prices" do
    field :eur_per_kwh, :decimal
    # ISO date as text ("YYYY-MM-DD"), unique.
    field :valid_from, :string
    timestamps()
  end
end
