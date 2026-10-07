defmodule Ziwoas.Economics.SavingsCalculator do
  @moduledoc """
  What a day's self-consumption was worth: the energy the measured consumers
  took straight from the array, priced at the electricity price in force that
  day. Exported energy earns nothing and never enters here (ADR-0003).
  """
  alias Ziwoas.Energy
  alias Ziwoas.Economics.PriceBook

  @enforce_keys [:price_book]
  defstruct [:price_book]

  @type t :: %__MODULE__{price_book: PriceBook.t()}

  @spec new(PriceBook.t()) :: t
  def new(%PriceBook{} = price_book), do: %__MODULE__{price_book: price_book}

  @doc "No price on record means the savings are unknown, not zero — a kWh is never free."
  @spec priced?(t) :: boolean
  def priced?(%__MODULE__{price_book: book}), do: not PriceBook.empty?(book)

  @spec savings_eur(t, Energy.t(), Date.t()) :: float | nil
  def savings_eur(%__MODULE__{price_book: book}, %Energy{} = energy, date) do
    case PriceBook.on(book, date) do
      nil -> nil
      price -> if Energy.negative?(energy), do: 0.0, else: Energy.kwh(energy) * price
    end
  end

  @doc "Each day at its own price, summed; nil without a price."
  @spec total_eur(t, [{Date.t(), Energy.t()}]) :: float | nil
  def total_eur(calculator, dated_energies) do
    if priced?(calculator) do
      Enum.reduce(dated_energies, 0.0, fn {date, energy}, total ->
        total + savings_eur(calculator, energy, date)
      end)
    end
  end
end
