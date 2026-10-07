defmodule Ziwoas.Economics.CostItem do
  @moduledoc "One amount spent on the plant on one date (`cost_items`). Negative amounts are subsidies."
  use Ziwoas.Schema

  @type t :: %__MODULE__{}

  schema "cost_items" do
    field :amount_eur, :decimal
    field :label, :string
    field :note, :string
    # ISO date as text ("YYYY-MM-DD"), not a date column.
    field :spent_on, :string
    timestamps()
  end
end
