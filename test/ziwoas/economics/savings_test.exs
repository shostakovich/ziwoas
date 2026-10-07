defmodule Ziwoas.Economics.SavingsTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Economics
  alias Ziwoas.Energy.Amount

  setup do
    {:ok, book: [{~D[2026-01-01], 0.30}, {~D[2026-07-01], 0.20}]}
  end

  test "a price applies from its date until the next one begins" do
    prices = [{~D[2026-01-01], 0.30}, {~D[2026-07-01], 0.25}]

    assert Economics.price_on(prices, ~D[2026-01-01]) == 0.30
    assert Economics.price_on(prices, ~D[2026-06-30]) == 0.30
    assert Economics.price_on(prices, ~D[2026-07-01]) == 0.25
    assert Economics.price_on(prices, ~D[2030-01-01]) == 0.25
  end

  test "the earliest price also covers every day before it; no prices know no price" do
    assert Economics.price_on([{~D[2026-01-01], 0.30}], ~D[2020-05-05]) == 0.30
    assert Economics.price_on([], ~D[2026-01-01]) == nil
  end

  test "prices a day's self-consumption at that day's price", %{book: book} do
    assert Economics.savings_eur(book, Amount.wh(2_000), ~D[2026-03-01]) == 0.6
    assert_in_delta Economics.savings_eur(book, Amount.wh(2_000), ~D[2026-07-01]), 0.4, 1.0e-12
  end

  test "nothing consumed is worth nothing, a negative balance too", %{book: book} do
    assert Economics.savings_eur(book, Amount.zero(), ~D[2026-03-01]) == 0.0
    assert Economics.savings_eur(book, Amount.wh(-500), ~D[2026-03-01]) == 0.0
  end

  test "sums a range day by day at each day's price", %{book: book} do
    days = [{~D[2026-06-30], Amount.wh(1_000)}, {~D[2026-07-01], Amount.wh(1_000)}]

    assert_in_delta Economics.total_savings_eur(book, days), 0.5, 1.0e-12
    assert Economics.total_savings_eur(book, []) === 0.0
  end

  test "without a price the savings are unknown, not zero" do
    book = []

    refute Economics.priced?(book)
    assert Economics.savings_eur(book, Amount.wh(1_000), ~D[2026-03-01]) == nil
    assert Economics.total_savings_eur(book, [{~D[2026-03-01], Amount.wh(1_000)}]) == nil
  end
end
