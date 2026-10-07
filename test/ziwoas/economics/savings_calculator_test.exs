defmodule Ziwoas.Economics.SavingsCalculatorTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Economics.{PriceBook, SavingsCalculator}
  alias Ziwoas.Energy

  defp book(entries) do
    entries
    |> Enum.map(fn {date, price} -> %PriceBook.Entry{valid_from: date, eur_per_kwh: price} end)
    |> PriceBook.new()
  end

  setup do
    calculator =
      SavingsCalculator.new(book([{~D[2026-01-01], 0.30}, {~D[2026-07-01], 0.20}]))

    {:ok, calculator: calculator}
  end

  test "prices a day's self-consumption at that day's price", %{calculator: calculator} do
    assert SavingsCalculator.savings_eur(calculator, Energy.wh(2_000), ~D[2026-03-01]) ==
             0.6

    assert_in_delta SavingsCalculator.savings_eur(calculator, Energy.wh(2_000), ~D[2026-07-01]),
                    0.4,
                    1.0e-12
  end

  test "nothing consumed is worth nothing, a negative balance too", %{calculator: calculator} do
    assert SavingsCalculator.savings_eur(calculator, Energy.zero(), ~D[2026-03-01]) == 0.0
    assert SavingsCalculator.savings_eur(calculator, Energy.wh(-500), ~D[2026-03-01]) == 0.0
  end

  test "sums a range day by day at each day's price", %{calculator: calculator} do
    days = [
      {~D[2026-06-30], Energy.wh(1_000)},
      {~D[2026-07-01], Energy.wh(1_000)}
    ]

    assert_in_delta SavingsCalculator.total_eur(calculator, days), 0.5, 1.0e-12
    assert SavingsCalculator.total_eur(calculator, []) === 0.0
  end

  test "without a price the savings are unknown, not zero" do
    calculator = SavingsCalculator.new(book([]))

    refute SavingsCalculator.priced?(calculator)
    assert SavingsCalculator.savings_eur(calculator, Energy.wh(1_000), ~D[2026-03-01]) == nil
    assert SavingsCalculator.total_eur(calculator, [{~D[2026-03-01], Energy.wh(1_000)}]) == nil
  end
end
