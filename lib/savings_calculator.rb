require "price_book"

# What a day's self-consumption was worth: the energy the measured consumers took
# straight from the array, priced at the electricity price in force that day.
# Exported energy earns nothing and never enters here (ADR-0003).
class SavingsCalculator
  def initialize(price_book:)
    @price_book = price_book
  end

  # No price on record means the savings are unknown, not zero — a kilowatt-hour
  # is never free.
  def priced? = !@price_book.empty?

  def savings_eur(energy, on:)
    price = @price_book.on(on)
    return nil if price.nil?
    return 0.0 if energy.negative?

    energy.kwh * price
  end

  def total_eur(dated_energies)
    return nil unless priced?

    dated_energies.sum { |date, energy| savings_eur(energy, on: date) }
  end
end
