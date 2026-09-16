module Economics
  module Forms
    # One Kostenposten as typed: a label, an amount that may be negative
    # (a subsidy), a date, and an optional note.
    class CostItem < Dry::Validation::Contract
      params do
        required(:label).maybe(:string)
        required(:amount_eur).maybe(:string)
        required(:spent_on).maybe(:string)
        optional(:note).maybe(:string)
      end

      rule(:label) do
        key.failure(MESSAGES[:label]) if value.blank?
      end

      rule(:amount_eur) do
        key.failure(MESSAGES[:amount]) unless Forms::CostItem.amount(value)
      end

      rule(:spent_on) do
        key.failure(MESSAGES[:date]) unless Forms.date?(value)
      end

      # German keyboards type a comma; the record stores a number either way.
      def self.amount(value)
        Float(value.to_s.tr(",", "."))
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
