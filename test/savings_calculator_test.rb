require "test_helper"
require "savings_calculator"
require "price_book"

class SavingsCalculatorTest < Minitest::Test
  cover "SavingsCalculator*"

  def book(entries = [ [ "2026-01-01", 0.32 ] ])
    PriceBook.new(entries.map { |from, price| PriceBook::Entry.new(valid_from: Date.iso8601(from), eur_per_kwh: price) })
  end

  def test_savings_price_the_self_consumed_energy_of_that_day
    calc = SavingsCalculator.new(price_book: book)

    assert_in_delta 0.32, calc.savings_eur(Energy.wh(1_000.0), on: Date.new(2026, 5, 1))
    assert_in_delta 0.0,  calc.savings_eur(Energy.zero,        on: Date.new(2026, 5, 1))
    assert_in_delta 0.08, calc.savings_eur(Energy.wh(250.0),   on: Date.new(2026, 5, 1))
  end

  def test_each_day_is_priced_with_the_price_in_force_on_it
    calc = SavingsCalculator.new(price_book: book([ [ "2026-01-01", 0.30 ], [ "2026-06-01", 0.20 ] ]))

    assert_in_delta 0.30, calc.savings_eur(Energy.wh(1_000.0), on: Date.new(2026, 5, 31))
    assert_in_delta 0.20, calc.savings_eur(Energy.wh(1_000.0), on: Date.new(2026, 6, 1))
  end

  def test_negative_energy_yields_zero_savings
    calc = SavingsCalculator.new(price_book: book)

    assert_in_delta 0.0, calc.savings_eur(Energy.wh(-50.0), on: Date.new(2026, 5, 1))
  end

  def test_without_a_price_there_is_no_amount_rather_than_a_free_kilowatt_hour
    calc = SavingsCalculator.new(price_book: book([]))

    assert_nil calc.savings_eur(Energy.wh(1_000.0), on: Date.new(2026, 5, 1))
    refute_predicate calc, :priced?
  end

  def test_a_calculator_with_prices_is_priced
    assert_predicate SavingsCalculator.new(price_book: book), :priced?
  end

  def test_total_prices_every_day_on_its_own
    calc = SavingsCalculator.new(price_book: book([ [ "2026-01-01", 0.30 ], [ "2026-06-01", 0.20 ] ]))

    total = calc.total_eur([
      [ Date.new(2026, 5, 31), Energy.wh(1_000.0) ],
      [ Date.new(2026, 6, 1),  Energy.wh(1_000.0) ]
    ])

    assert_in_delta 0.50, total
  end

  def test_total_without_prices_is_unknown
    calc = SavingsCalculator.new(price_book: book([]))

    assert_nil calc.total_eur([ [ Date.new(2026, 5, 31), Energy.wh(1_000.0) ] ])
  end
end
