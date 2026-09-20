module Economics
  module Forms
    # One Strompreis as typed: what a kilowatt-hour costs from a date on.
    class ElectricityPrice < Dry::Validation::Contract
      params do
        required(:eur_per_kwh).maybe(:string)
        required(:valid_from).maybe(:string)
      end

      rule(:eur_per_kwh) do
        price = Forms::CostItem.amount(value)
        key.failure(MESSAGES[:price]) if price.nil? || price <= 0
      end

      rule(:valid_from) do
        key.failure(MESSAGES[:date]) unless Forms.date?(value)
      end
    end
  end
end
