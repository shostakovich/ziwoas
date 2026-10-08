defmodule Ziwoas.Economics do
  @moduledoc false
  import Ecto.Query

  alias Ziwoas.Economics.{CostItem, ElectricityPrice, Overview, Payback}
  alias Ziwoas.Energy
  alias Ziwoas.Energy.Amount
  alias Ziwoas.Repo

  @type kwh_prices :: [{Date.t(), float}]

  @spec kwh_prices() :: kwh_prices
  def kwh_prices do
    from(p in ElectricityPrice, order_by: p.valid_from)
    |> Repo.all()
    |> Enum.map(&{&1.valid_from, to_float(&1.eur_per_kwh, 5)})
  end

  @doc "The price in force on `date`; the earliest price also covers the days before it."
  @spec price_on(kwh_prices, Date.t()) :: float | nil
  def price_on([], _date), do: nil

  def price_on([{_from, earliest} | _] = prices, %Date{} = date) do
    Enum.reduce_while(prices, earliest, fn {from, eur}, price ->
      if Date.after?(from, date), do: {:halt, price}, else: {:cont, eur}
    end)
  end

  @spec priced?(kwh_prices) :: boolean
  def priced?(prices), do: prices != []

  @spec savings_eur(kwh_prices, Amount.t(), Date.t()) :: float | nil
  def savings_eur(prices, %Amount{} = energy, %Date{} = date) do
    case price_on(prices, date) do
      nil -> nil
      price -> if Amount.negative?(energy), do: 0.0, else: Amount.kwh(energy) * price
    end
  end

  @spec total_savings_eur(kwh_prices, [{Date.t(), Amount.t()}]) :: float | nil
  def total_savings_eur(prices, dated_energies) do
    if priced?(prices) do
      Enum.reduce(dated_energies, 0.0, fn {date, energy}, total ->
        total + savings_eur(prices, energy, date)
      end)
    end
  end

  @spec overview(Date.t()) :: Overview.t()
  def overview(%Date{} = today) do
    prices = kwh_prices()
    priced = priced?(prices)
    summaries = Energy.daily_summaries()
    cost = total_cost_eur()
    payback = Payback.new(cost, daily_savings(summaries, prices, priced), today)

    %Overview{
      saved_eur: if(priced, do: Payback.saved_eur(payback)),
      acquisition_cost_eur: cost,
      covered_ratio: if(priced, do: Payback.covered_ratio(payback)),
      data_start: first_date(summaries),
      projected_payback_date: if(priced, do: Payback.projected_date(payback)),
      reached_on: if(priced, do: Payback.reached_on(payback)),
      projection_days: Payback.projection_days(payback),
      priced: priced,
      costed: Payback.costed?(payback)
    }
  end

  defp first_date([first | _]), do: first.date
  defp first_date([]), do: nil

  defp daily_savings(_summaries, _prices, false), do: []

  defp daily_savings(summaries, prices, true) do
    Enum.map(summaries, fn summary ->
      {summary.date, savings_eur(prices, Amount.wh(summary.self_consumed_wh), summary.date)}
    end)
  end

  @spec cost_items() :: [CostItem.t()]
  def cost_items do
    Repo.all(from c in CostItem, order_by: [desc: c.spent_on, desc: c.id])
  end

  @spec prices() :: [ElectricityPrice.t()]
  def prices, do: Repo.all(from p in ElectricityPrice, order_by: [desc: p.valid_from])

  @spec total_cost_eur() :: float
  def total_cost_eur do
    from(c in CostItem, select: c.amount_eur)
    |> Repo.all()
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    |> to_float(2)
  end

  @spec new_cost_item(Date.t()) :: Ecto.Changeset.t()
  def new_cost_item(%Date{} = spent_on),
    do: CostItem.changeset(%CostItem{spent_on: spent_on}, %{})

  @spec change_cost_item(map) :: Ecto.Changeset.t()
  def change_cost_item(attrs), do: CostItem.changeset(%CostItem{}, attrs)

  @spec create_cost_item(map) :: {:ok, CostItem.t()} | {:error, Ecto.Changeset.t()}
  def create_cost_item(attrs), do: %CostItem{} |> CostItem.changeset(attrs) |> Repo.insert()

  @spec new_price(Date.t()) :: Ecto.Changeset.t()
  def new_price(%Date{} = valid_from),
    do: ElectricityPrice.changeset(%ElectricityPrice{valid_from: valid_from}, %{})

  @spec change_price(map) :: Ecto.Changeset.t()
  def change_price(attrs), do: ElectricityPrice.changeset(%ElectricityPrice{}, attrs)

  @spec create_price(map) :: {:ok, ElectricityPrice.t()} | {:error, Ecto.Changeset.t()}
  def create_price(attrs),
    do: %ElectricityPrice{} |> ElectricityPrice.changeset(attrs) |> Repo.insert()

  @spec delete_cost_item(term) :: {:ok, CostItem.t()} | {:error, :not_found}
  def delete_cost_item(id), do: delete(CostItem, id)

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

  # SQLite stores DECIMAL as REAL, so values may carry binary noise beyond the scale.
  defp to_float(%Decimal{} = value, scale),
    do: value |> Decimal.round(scale) |> Decimal.to_float()
end
