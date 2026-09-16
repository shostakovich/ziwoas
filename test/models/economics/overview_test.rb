require "test_helper"

class Economics::OverviewTest < ActiveSupport::TestCase
  cover "Economics::Overview*"

  setup do
    DailyEnergySummary.delete_all
    Economics::CostItem.delete_all
    Economics::ElectricityPrice.delete_all
  end

  test "savings price each day's self-consumption, never its production" do
    price("2026-01-01", 0.30)
    seed("2026-04-01", produced: 10_000.0, self_consumed: 1_000.0)
    seed("2026-04-02", produced: 10_000.0, self_consumed: 2_000.0)

    assert_in_delta 0.90, build.saved_eur
  end

  test "each day is priced with the price in force on it" do
    price("2026-01-01", 0.30)
    price("2026-04-02", 0.20)
    seed("2026-04-01", self_consumed: 1_000.0)
    seed("2026-04-02", self_consumed: 1_000.0)

    assert_in_delta 0.50, build.saved_eur
  end

  test "without a price the savings are unknown rather than zero" do
    seed("2026-04-01", self_consumed: 1_000.0)

    overview = build
    assert_not overview.priced?
    assert_nil overview.saved_eur
  end

  test "data start is the first day on record" do
    price("2026-01-01", 0.30)
    seed("2026-04-02", self_consumed: 1_000.0)
    seed("2026-04-01", self_consumed: 1_000.0)

    assert_equal Date.new(2026, 4, 1), build.data_start
  end

  test "acquisition cost sums the cost items including negative ones" do
    price("2026-01-01", 0.30)
    cost("Module", 1_200.00, "2026-01-05")
    cost("Förderung", -200.00, "2026-02-01")

    overview = build
    assert_in_delta 1_000.0, overview.acquisition_cost_eur
    assert_predicate overview, :costed?
  end

  test "without cost items nothing is costed" do
    price("2026-01-01", 0.30)

    assert_not build.costed?
  end

  test "a long enough record projects a payback date" do
    price("2026-01-01", 0.30)
    100.times { |i| seed((Date.new(2026, 1, 1) + i).to_s, self_consumed: 10_000.0) }
    cost("Anlage", 600.00, "2026-01-01")

    overview = build(today: Date.new(2026, 4, 10))
    # 100 days at 3 € each is 300 €; 300 € left at 3 €/day lands 100 days on.
    assert_in_delta 300.0, overview.saved_eur
    assert_equal Date.new(2026, 4, 10) + 100, overview.projected_payback_date
    assert_in_delta 0.5, overview.covered_ratio
  end

  test "a short record reports its length instead of a date" do
    price("2026-01-01", 0.30)
    10.times { |i| seed((Date.new(2026, 1, 1) + i).to_s, self_consumed: 10_000.0) }
    cost("Anlage", 600.00, "2026-01-01")

    overview = build(today: Date.new(2026, 1, 10))
    assert_nil overview.projected_payback_date
    assert_equal 10, overview.projection_days
  end

  private

  def build(today: Date.new(2026, 9, 1))
    Economics::Overview.new(today: today).build
  end

  def seed(date, self_consumed:, produced: 20_000.0, consumed: 5_000.0)
    DailyEnergySummary.create!(date: date, produced_wh: produced, consumed_wh: consumed,
                              self_consumed_wh: self_consumed)
  end

  def price(valid_from, eur_per_kwh)
    Economics::ElectricityPrice.create!(valid_from: valid_from, eur_per_kwh: eur_per_kwh)
  end

  def cost(label, amount_eur, spent_on)
    Economics::CostItem.create!(label: label, amount_eur: amount_eur, spent_on: spent_on)
  end
end
