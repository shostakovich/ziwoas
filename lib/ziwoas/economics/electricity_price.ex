defmodule Ziwoas.Economics.ElectricityPrice do
  @moduledoc false
  use Ziwoas.Schema

  import Ecto.Changeset

  alias Ziwoas.Economics.DecimalInput

  @type t :: %__MODULE__{}

  @price_message "Preis muss größer als 0 sein"
  @date_message "Datum angeben"
  # DECIMAL(8, 5): three digits before the point.
  @price_limit 1000

  schema "electricity_prices" do
    field :eur_per_kwh, :decimal
    field :valid_from, :date
    timestamps()
  end

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
    |> update_change(:eur_per_kwh, &DecimalInput.round_below(&1, 5, @price_limit))
    |> validate_number(:eur_per_kwh, greater_than: 0, message: @price_message)
    |> validate_number(:eur_per_kwh, less_than: @price_limit, message: "Preis ist zu hoch")
    |> unique_constraint(:valid_from, message: "Für dieses Datum gibt es bereits einen Preis")
  end
end
