require "price_book"

module Economics
  # What a kilowatt-hour from the grid costs from a date on. The rows together
  # are the PriceBook every savings figure is read against.
  class ElectricityPrice < ApplicationRecord
    self.table_name = "electricity_prices"

    validates :eur_per_kwh, presence: true, numericality: { greater_than: 0 }
    validates :valid_from, presence: true,
                           uniqueness: true,
                           format: { with: /\A\d{4}-\d{2}-\d{2}\z/, message: "must be YYYY-MM-DD" }

    scope :newest_first, -> { order(valid_from: :desc) }

    def self.book
      PriceBook.new(all.map { |row| PriceBook::Entry.new(valid_from: row.date, eur_per_kwh: row.eur_per_kwh.to_f) })
    end

    def date = Date.iso8601(valid_from)
  end
end
