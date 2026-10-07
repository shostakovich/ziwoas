defmodule Ziwoas.Economics.ElectricityPrice do
  @moduledoc "Price per kWh valid from a date on (`electricity_prices`, one per date)."
  use Ziwoas.Schema

  import Ecto.Changeset

  alias Ziwoas.Economics.DecimalInput

  @type t :: %__MODULE__{}

  @price_message "Preis muss größer als 0 sein"
  @date_message "Datum angeben"

  schema "electricity_prices" do
    field :eur_per_kwh, :decimal
    field :valid_from, :date
    timestamps()
  end

  @doc """
  A Strompreis as typed. The price is kept to the column's five decimals and
  must stay above zero after that.
  """
  @spec changeset(t, map) :: Ecto.Changeset.t()
  def changeset(price, attrs) do
    price
    |> cast(DecimalInput.normalize(attrs, "eur_per_kwh"), [:eur_per_kwh, :valid_from],
      message: fn
        :eur_per_kwh, _meta -> @price_message
        :valid_from, _meta -> @date_message
      end
    )
    |> validate_required(:eur_per_kwh, message: @price_message)
    |> validate_required(:valid_from, message: @date_message)
    |> update_change(:eur_per_kwh, &Decimal.round(&1, 5))
    |> validate_number(:eur_per_kwh, greater_than: 0, message: @price_message)
    # DECIMAL(8, 5): three digits before the point.
    |> validate_number(:eur_per_kwh, less_than: 1000, message: "Preis ist zu hoch")
    |> unique_constraint(:valid_from, message: "Für dieses Datum gibt es bereits einen Preis")
  end
end
