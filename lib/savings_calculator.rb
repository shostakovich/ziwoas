class SavingsCalculator
  def initialize(price_eur_per_kwh:)
    @price = price_eur_per_kwh
  end

  def savings_eur(energy)
    return 0.0 if energy.negative?

    energy.kwh * @price
  end
end
