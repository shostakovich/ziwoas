defmodule Ziwoas.Economics do
  @moduledoc """
  What the plant cost and what grid electricity costs, read from the database.
  DECIMAL columns are read the way Rails reads them (`Ziwoas.Economics.DecimalColumn`)
  and are floats from there on.
  """
  import Ecto.Query

  alias Ziwoas.{Form, Repo, RubyNumeric}
  alias Ziwoas.Economics.{CostItem, DecimalColumn, ElectricityPrice, Forms, PriceBook}

  @doc "Every recorded electricity price as a `PriceBook`."
  @spec price_book() :: PriceBook.t()
  def price_book do
    from(p in ElectricityPrice, select: {p.valid_from, fragment("?", p.eur_per_kwh)})
    |> Repo.all()
    |> Enum.map(fn {valid_from, eur_per_kwh} ->
      %PriceBook.Entry{
        valid_from: Date.from_iso8601!(valid_from),
        eur_per_kwh: DecimalColumn.to_float(eur_per_kwh, 8, 5)
      }
    end)
    |> PriceBook.new()
  end

  @doc "The cost items, newest first (`CostItem.newest_first`), amounts as Rails reads them."
  @spec cost_items() :: [CostItem.t()]
  def cost_items do
    from(c in CostItem,
      order_by: [desc: c.spent_on, desc: c.id],
      select: %{c | amount_eur: fragment("?", c.amount_eur)}
    )
    |> Repo.all()
    |> Enum.map(&%{&1 | amount_eur: DecimalColumn.to_float(&1.amount_eur, 10, 2)})
  end

  @doc "The electricity prices, newest first (`ElectricityPrice.newest_first`)."
  @spec prices() :: [ElectricityPrice.t()]
  def prices do
    from(p in ElectricityPrice,
      order_by: [desc: p.valid_from],
      select: %{p | eur_per_kwh: fragment("?", p.eur_per_kwh)}
    )
    |> Repo.all()
    |> Enum.map(&%{&1 | eur_per_kwh: DecimalColumn.to_float(&1.eur_per_kwh, 8, 5)})
  end

  @doc """
  Records a cost item from a valid `Forms.CostItem` changeset's changes
  (`CostItemsController#create`): the amount through the column's rounding,
  the date as ISO text, a blank note as none.
  """
  @spec create_cost_item!(map, Date.t()) :: CostItem.t()
  def create_cost_item!(attrs, today) do
    Repo.write(:economics, fn ->
      Repo.insert!(%CostItem{
        label: attrs.label,
        amount_eur: decimal(Forms.amount(attrs.amount_eur), 10, 2),
        spent_on: Date.to_iso8601(Forms.date(attrs.spent_on, today)),
        note: presence(attrs[:note])
      })
    end)
  end

  @doc """
  Records a price from a valid `Forms.ElectricityPrice` changeset's changes,
  or answers the record's own refusal (`ElectricityPricesController#create`):
  a date that already has a price, else a price that rounds away to zero in
  the column.
  """
  @spec create_price(map, Date.t()) :: {:ok, ElectricityPrice.t()} | {:error, String.t()}
  def create_price(attrs, today) do
    valid_from = Date.to_iso8601(Forms.date(attrs.valid_from, today))
    eur_per_kwh = DecimalColumn.cast(Forms.amount(attrs.eur_per_kwh), 8, 5)

    Repo.write(:economics, fn ->
      cond do
        Repo.exists?(from p in ElectricityPrice, where: p.valid_from == ^valid_from) ->
          {:error, "Für dieses Datum gibt es bereits einen Preis"}

        eur_per_kwh <= 0 ->
          {:error, Forms.message(:price)}

        true ->
          {:ok,
           Repo.insert!(%ElectricityPrice{
             valid_from: valid_from,
             eur_per_kwh: Decimal.from_float(eur_per_kwh)
           })}
      end
    end)
  end

  @doc "Deletes the cost item `id` names, if there is one (`find_by(id:)&.destroy`)."
  @spec delete_cost_item(term) :: :ok
  def delete_cost_item(id), do: delete(CostItem, id)

  @doc "Deletes the price `id` names, if there is one."
  @spec delete_price(term) :: :ok
  def delete_price(id), do: delete(ElectricityPrice, id)

  defp delete(schema, id) do
    with {:ok, id} <- RubyNumeric.integer(id) do
      Repo.write(:economics, fn ->
        if record = Repo.get(schema, id), do: Repo.delete!(record)
      end)
    end

    :ok
  end

  defp decimal(amount, precision, scale),
    do: amount |> DecimalColumn.cast(precision, scale) |> Decimal.from_float()

  defp presence(value), do: if(Form.blank?(value), do: nil, else: value)

  @doc "The sum of all cost items, subsidies and refunds included; 0.0 without any."
  @spec total_cost_eur() :: float
  def total_cost_eur do
    sum = Repo.one(from c in CostItem, select: fragment("SUM(?)", c.amount_eur))
    DecimalColumn.to_float(sum || 0, 10, 2)
  end
end
