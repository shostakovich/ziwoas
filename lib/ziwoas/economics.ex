defmodule Ziwoas.Economics do
  @moduledoc """
  What the plant cost, what grid electricity costs (read from the database,
  ADR-0004) and what the self-consumption saved. The lists keep their
  `Decimal`s; the figures the savings are reckoned with are floats.

  Savings count only the energy the measured consumers took straight from the
  array, priced at the electricity price in force that day. Exported energy
  earns nothing (ADR-0003).
  """
  import Ecto.Query

  alias Ziwoas.Economics.{CostItem, ElectricityPrice, Overview, Payback}
  alias Ziwoas.Energy
  alias Ziwoas.Energy.Amount
  alias Ziwoas.Repo

  @typedoc "The electricity prices per kWh as `{valid_from, eur}`, oldest first."
  @type kwh_prices :: [{Date.t(), float}]

  @doc "Every recorded electricity price per kWh, oldest first."
  @spec kwh_prices() :: kwh_prices
  def kwh_prices do
    from(p in ElectricityPrice, order_by: p.valid_from)
    |> Repo.all()
    |> Enum.map(&{&1.valid_from, to_float(&1.eur_per_kwh, 5)})
  end

  @doc """
  The price per kWh in force on `date`: a price applies from its date until the
  next one begins; the earliest also covers every day before it, because a plant
  that ran before the first price was recorded still saved money. Nil without
  prices.
  """
  @spec price_on(kwh_prices, Date.t()) :: float | nil
  def price_on([], _date), do: nil

  def price_on([{_from, earliest} | _] = prices, %Date{} = date) do
    Enum.reduce_while(prices, earliest, fn {from, eur}, price ->
      if Date.after?(from, date), do: {:halt, price}, else: {:cont, eur}
    end)
  end

  @doc "No price on record means the savings are unknown, not zero — a kWh is never free."
  @spec priced?(kwh_prices) :: boolean
  def priced?(prices), do: prices != []

  @doc "What a day's self-consumption was worth at its price; nil without a price, 0.0 for none."
  @spec savings_eur(kwh_prices, Amount.t(), Date.t()) :: float | nil
  def savings_eur(prices, %Amount{} = energy, %Date{} = date) do
    case price_on(prices, date) do
      nil -> nil
      price -> if Amount.negative?(energy), do: 0.0, else: Amount.kwh(energy) * price
    end
  end

  @doc "Each day at its own price, summed; nil without a price."
  @spec total_savings_eur(kwh_prices, [{Date.t(), Amount.t()}]) :: float | nil
  def total_savings_eur(prices, dated_energies) do
    if priced?(prices) do
      Enum.reduce(dated_energies, 0.0, fn {date, energy}, total ->
        total + savings_eur(prices, energy, date)
      end)
    end
  end

  @doc """
  Everything the Wirtschaftlichkeit card shows, as of `today`: the daily
  self-consumption on record, priced day by day, against what the plant
  cost. Without a price, the money figures are unknown (nil), not zero.
  """
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
