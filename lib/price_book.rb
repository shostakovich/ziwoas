require "date"

# The electricity prices in force over time. A price applies from its date until
# the next one begins; the earliest one also covers every day before it, because
# a plant that ran before the first price was recorded still saved money.
class PriceBook
  Entry = Data.define(:valid_from, :eur_per_kwh)

  def initialize(entries)
    @entries = entries.sort_by(&:valid_from)
  end

  def empty? = @entries.empty?

  def on(date)
    applicable = @entries.reverse_each.find { |entry| entry.valid_from <= date }
    (applicable || @entries.first)&.eur_per_kwh
  end
end
