defmodule Ziwoas.Economics.CostItem do
  @moduledoc "One amount spent on the plant on one date (`cost_items`). Negative amounts are subsidies."
  use Ziwoas.Schema

  import Ecto.Changeset

  alias Ziwoas.Economics.DecimalInput

  @type t :: %__MODULE__{}

  schema "cost_items" do
    field :amount_eur, :decimal
    field :label, :string
    field :note, :string
    field :spent_on, :date
    timestamps()
  end

  @doc "A Kostenposten as typed: German keyboards type a decimal comma."
  @spec changeset(t, map) :: Ecto.Changeset.t()
  def changeset(item, attrs) do
    item
    |> cast(DecimalInput.normalize(attrs, "amount_eur"), [:label, :amount_eur, :spent_on, :note],
      message: &cast_message/2
    )
    |> validate_required(:label, message: "Bezeichnung angeben")
    |> validate_required(:amount_eur, message: "Betrag als Zahl angeben")
    |> validate_required(:spent_on, message: "Datum angeben")
    |> update_change(:amount_eur, &Decimal.round(&1, 2))
    |> validate_change(:amount_eur, &within_column/2)
  end

  # DECIMAL(10, 2): eight digits before the point.
  defp within_column(field, amount) do
    if Decimal.lt?(Decimal.abs(amount), 100_000_000),
      do: [],
      else: [{field, "Betrag ist zu groß"}]
  end

  defp cast_message(:amount_eur, _meta), do: "Betrag als Zahl angeben"
  defp cast_message(:spent_on, _meta), do: "Datum angeben"
  defp cast_message(_field, _meta), do: nil
end
