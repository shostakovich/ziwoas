require "test_helper"
require "price_book"

class PriceBookTest < ActiveSupport::TestCase
  cover "PriceBook*"

  test "a price applies from its date until the next one begins" do
    book = PriceBook.new([ entry("2026-01-01", 0.30), entry("2026-06-01", 0.25) ])

    assert_in_delta 0.30, book.on(Date.new(2026, 1, 1))
    assert_in_delta 0.30, book.on(Date.new(2026, 5, 31))
    assert_in_delta 0.25, book.on(Date.new(2026, 6, 1))
    assert_in_delta 0.25, book.on(Date.new(2027, 3, 4))
  end

  test "the earliest price also covers the days before it" do
    book = PriceBook.new([ entry("2026-06-01", 0.25) ])

    assert_in_delta 0.25, book.on(Date.new(2020, 1, 1))
  end

  test "entries need not arrive in order" do
    book = PriceBook.new([ entry("2026-06-01", 0.25), entry("2026-01-01", 0.30) ])

    assert_in_delta 0.30, book.on(Date.new(2026, 3, 1))
  end

  test "unsorted entries still resolve to the price most recently in force, not merely any past one" do
    # Inserted out of chronological order: the 2026-03-01 entry sits between the
    # other two in the array, not at the end. Without sorting, #on's reverse scan
    # meets 2026-01-01 before 2026-03-01 and would answer with the wrong price.
    book = PriceBook.new([ entry("2026-03-01", 0.10), entry("2026-01-01", 0.20), entry("2026-06-01", 0.30) ])

    assert_in_delta 0.10, book.on(Date.new(2026, 4, 1))
  end

  test "an empty book knows no price" do
    book = PriceBook.new([])

    assert_nil book.on(Date.new(2026, 1, 1))
    assert_predicate book, :empty?
  end

  test "a book with entries is not empty" do
    refute_predicate PriceBook.new([ entry("2026-01-01", 0.30) ]), :empty?
  end

  private

  def entry(valid_from, eur_per_kwh)
    PriceBook::Entry.new(valid_from: Date.iso8601(valid_from), eur_per_kwh: eur_per_kwh)
  end
end
