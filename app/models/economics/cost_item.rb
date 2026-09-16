module Economics
  # One amount spent on the plant on one date. Negative amounts are subsidies and
  # refunds — they belong in the same list, because the sum is what matters.
  class CostItem < ApplicationRecord
    self.table_name = "cost_items"

    validates :label, presence: true
    validates :amount_eur, presence: true, numericality: true
    validates :spent_on, presence: true,
                         format: { with: /\A\d{4}-\d{2}-\d{2}\z/, message: "must be YYYY-MM-DD" }

    scope :newest_first, -> { order(spent_on: :desc, id: :desc) }

    def self.total_eur = sum(:amount_eur).to_f

    def date = Date.iso8601(spent_on)
  end
end
