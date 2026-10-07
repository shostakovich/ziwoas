defmodule Ziwoas.Economics do
  @moduledoc """
  What the plant cost and what grid electricity costs, read from the database
  (ADR-0004). The lists keep their `Decimal`s; the figures the savings are
  reckoned with are floats.
  """
  import Ecto.Query

  alias Ziwoas.Repo
  alias Ziwoas.Economics.{CostItem, ElectricityPrice, PriceBook}

  @doc "Every recorded electricity price as a `PriceBook`."
  @spec price_book() :: PriceBook.t()
  def price_book do
    ElectricityPrice
    |> Repo.all()
    |> Enum.map(fn price ->
      %PriceBook.Entry{
        valid_from: Date.from_iso8601!(price.valid_from),
        eur_per_kwh: to_float(price.eur_per_kwh, 5)
      }
    end)
    |> PriceBook.new()
  end

  @doc "The cost items, newest first."
  @spec cost_items() :: [CostItem.t()]
  def cost_items do
    Repo.all(from c in CostItem, order_by: [desc: c.spent_on, desc: c.id])
  end

  @doc "The electricity prices, newest first."
  @spec prices() :: [ElectricityPrice.t()]
  def prices, do: Repo.all(from p in ElectricityPrice, order_by: [desc: p.valid_from])

  @doc "The sum of all cost items, subsidies and refunds included; 0.0 without any."
  @spec total_cost_eur() :: float
  def total_cost_eur do
    from(c in CostItem, select: c.amount_eur)
    |> Repo.all()
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    |> to_float(2)
  end

  @spec change_cost_item(CostItem.t(), map) :: Ecto.Changeset.t()
  def change_cost_item(%CostItem{} = item, attrs \\ %{}), do: CostItem.changeset(item, attrs)

  @spec create_cost_item(map) :: {:ok, CostItem.t()} | {:error, Ecto.Changeset.t()}
  def create_cost_item(attrs), do: %CostItem{} |> CostItem.changeset(attrs) |> Repo.insert()

  @spec change_price(ElectricityPrice.t(), map) :: Ecto.Changeset.t()
  def change_price(%ElectricityPrice{} = price, attrs \\ %{}),
    do: ElectricityPrice.changeset(price, attrs)

  @spec create_price(map) :: {:ok, ElectricityPrice.t()} | {:error, Ecto.Changeset.t()}
  def create_price(attrs),
    do: %ElectricityPrice{} |> ElectricityPrice.changeset(attrs) |> Repo.insert()

  @doc "Deletes the cost item `id` names; `{:error, :not_found}` if there is none."
  @spec delete_cost_item(term) :: {:ok, CostItem.t()} | {:error, :not_found}
  def delete_cost_item(id), do: delete(CostItem, id)

  @doc "Deletes the price `id` names; `{:error, :not_found}` if there is none."
  @spec delete_price(term) :: {:ok, ElectricityPrice.t()} | {:error, :not_found}
  def delete_price(id), do: delete(ElectricityPrice, id)

  defp delete(schema, id) do
    with {:ok, id} <- Ecto.Type.cast(:id, id),
         %{} = record <- Repo.get(schema, id) do
      Repo.delete(record)
    else
      _ -> {:error, :not_found}
    end
  end

  # SQLite stores DECIMAL as REAL: a sum, or a value written by another client,
  # may carry binary noise beyond the column's scale.
  defp to_float(%Decimal{} = value, scale),
    do: value |> Decimal.round(scale) |> Decimal.to_float()
end
