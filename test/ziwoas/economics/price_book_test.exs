defmodule Ziwoas.Economics.PriceBookTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Economics.PriceBook

  defp book(entries) do
    entries
    |> Enum.map(fn {date, price} -> %PriceBook.Entry{valid_from: date, eur_per_kwh: price} end)
    |> PriceBook.new()
  end

  test "a price applies from its date until the next one begins, entered in any order" do
    book = book([{~D[2026-07-01], 0.25}, {~D[2026-01-01], 0.30}])

    assert PriceBook.on(book, ~D[2026-01-01]) == 0.30
    assert PriceBook.on(book, ~D[2026-06-30]) == 0.30
    assert PriceBook.on(book, ~D[2026-07-01]) == 0.25
    assert PriceBook.on(book, ~D[2030-01-01]) == 0.25
  end

  test "the earliest price also covers every day before it" do
    assert PriceBook.on(book([{~D[2026-01-01], 0.30}]), ~D[2020-05-05]) == 0.30
  end

  test "an empty book knows no price" do
    book = book([])

    assert PriceBook.empty?(book)
    assert PriceBook.on(book, ~D[2026-01-01]) == nil
    refute PriceBook.empty?(book([{~D[2026-01-01], 0.30}]))
  end
end
