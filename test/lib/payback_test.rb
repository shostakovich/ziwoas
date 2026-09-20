require "test_helper"
require "payback"

class PaybackTest < ActiveSupport::TestCase
  cover "Payback*"

  # 200 days of one euro a day, against 1000 € of cost items.
  def steady(days: 200, per_day: 1.0, cost: 1000.0, today: Date.new(2026, 9, 1))
    first = today - (days - 1)
    Payback.new(
      acquisition_cost_eur: cost,
      daily_savings: (0...days).map { |i| [ first + i, per_day ] },
      today: today
    )
  end

  test "reports what was saved and which share of the cost it covers" do
    payback = steady

    assert_in_delta 200.0, payback.saved_eur
    assert_in_delta 0.2,   payback.covered_ratio
    assert_equal Date.new(2026, 2, 14), payback.data_start
  end

  test "projects the remaining cost at the average daily savings" do
    # 800 € left at 1 €/day lands 800 days after today.
    assert_equal Date.new(2026, 9, 1) + 800, steady.projected_date
  end

  test "the projection averages over the last 365 days only" do
    today = Date.new(2026, 9, 1)
    first = today - 499
    # 365 days ago the rate rises from 0.10 € to 2 € a day.
    dated = (0...500).map { |i| [ first + i, i < 135 ? 0.10 : 2.0 ] }
    payback = Payback.new(acquisition_cost_eur: 1000.0, daily_savings: dated, today: today)

    assert_in_delta 13.5 + 730.0, payback.saved_eur
    # Remaining 256.50 € at 2 €/day, not at the lifetime average.
    assert_equal today + 129, payback.projected_date
  end

  test "below ninety days of data no date is projected" do
    payback = steady(days: 89)

    assert_nil payback.projected_date
    assert_equal 89, payback.projection_days
  end

  test "at ninety days of data a date appears" do
    assert_not_nil steady(days: 90).projected_date
  end

  test "a reached payback reports the day it was reached instead of a projection" do
    payback = steady(days: 200, per_day: 10.0, cost: 1000.0)

    assert_predicate payback, :reached?
    # 1000 € at 10 €/day is reached on the hundredth day.
    assert_equal Date.new(2026, 2, 14) + 99, payback.reached_on
    assert_nil payback.projected_date
    assert_in_delta 1.0, payback.covered_ratio
  end

  test "covered ratio caps at one so the bar cannot overflow" do
    assert_in_delta 1.0, steady(days: 200, per_day: 10.0, cost: 100.0).covered_ratio
  end

  test "without cost items there is nothing to pay back" do
    payback = steady(cost: 0.0)

    refute_predicate payback, :costed?
    refute_predicate payback, :reached?
    assert_nil payback.projected_date
    assert_nil payback.covered_ratio
  end

  test "reached is true once savings equal the cost, not only once they exceed it" do
    payback = steady(days: 100, per_day: 10.0, cost: 1000.0)

    assert_predicate payback, :reached?
  end

  test "without an explicit today, the current date anchors the projection" do
    travel_to Date.new(2026, 9, 1) do
      days = (0...100).map { |i| [ Date.new(2026, 9, 1) - 99 + i, 1.0 ] }
      payback = Payback.new(acquisition_cost_eur: 200.0, daily_savings: days)

      assert_equal Date.new(2026, 9, 1) + 100, payback.projected_date
    end
  end

  test "daily savings need not arrive sorted by date" do
    today = Date.new(2026, 9, 1)
    scrambled = [
      [ today,     5.0 ],
      [ today - 2, 100.0 ],
      [ today - 1, 5.0 ]
    ]
    payback = Payback.new(acquisition_cost_eur: 100.0, daily_savings: scrambled, today: today)

    assert_equal today - 2, payback.data_start
    # Reached on the earliest day chronologically, not the earliest in the array.
    assert_equal today - 2, payback.reached_on
  end

  test "the projection window covers exactly the last 365 days, cutoff inclusive" do
    today = Date.new(2026, 9, 1)
    # 89 recent days plus one day exactly 364 days back (the 365th day of the
    # window) reach the 90-day minimum only if that boundary day is included.
    bulk = (1..89).map { |age| [ today - age, 1.0 ] }
    boundary_in  = [ today - 364, 1.0 ]       # last day still inside the window
    boundary_out = [ today - 365, 100_000.0 ] # one day older: must not count

    payback = Payback.new(
      acquisition_cost_eur: 200_000.0,
      daily_savings: bulk + [ boundary_in, boundary_out ],
      today: today
    )

    assert_equal today + 99_910, payback.projected_date
  end

  test "a spike above the running total that later falls back below cost is not reached" do
    today = Date.new(2026, 9, 1)
    payback = Payback.new(
      acquisition_cost_eur: 100.0,
      daily_savings: [ [ today - 1, 150.0 ], [ today, -100.0 ] ],
      today: today
    )

    refute_predicate payback, :reached?
    assert_nil payback.reached_on
  end

  test "the running total starts at zero, not off by a day's savings" do
    today = Date.new(2026, 9, 1)
    payback = Payback.new(
      acquisition_cost_eur: 5.0,
      daily_savings: [ [ today - 1, 4.0 ], [ today, 1.0 ] ],
      today: today
    )

    assert_equal today, payback.reached_on
  end

  test "reached_on returns the day the running total passes the cost, even when it overshoots" do
    today = Date.new(2026, 9, 1)
    payback = Payback.new(acquisition_cost_eur: 7.0, daily_savings: [ [ today, 10.0 ] ], today: today)

    assert_equal today, payback.reached_on
  end

  test "reached_on is nil, not the raw days, when floating-point summation never quite matches the cost" do
    today = Date.new(2026, 9, 1)
    amounts = Array.new(6, 0.1)
    cost = amounts.sum
    dated = Array.new(6) { |i| [ today - 5 + i, 0.1 ] }
    payback = Payback.new(acquisition_cost_eur: cost, daily_savings: dated, today: today)

    assert_predicate payback, :reached?
    assert_nil payback.reached_on
  end

  test "without savings days there is no data start and no projection" do
    payback = Payback.new(acquisition_cost_eur: 1000.0, daily_savings: [], today: Date.new(2026, 9, 1))

    assert_in_delta 0.0, payback.saved_eur
    assert_nil payback.data_start
    assert_nil payback.projected_date
    refute_predicate payback, :reached?
  end

  test "days without savings still count towards the projection basis" do
    today = Date.new(2026, 9, 1)
    first = today - 99
    # 100 days on record, half of them yielding nothing: 50 € over 100 days.
    dated = (0...100).map { |i| [ first + i, i.even? ? 1.0 : 0.0 ] }
    payback = Payback.new(acquisition_cost_eur: 100.0, daily_savings: dated, today: today)

    assert_in_delta 50.0, payback.saved_eur
    # 50 € left at 0.50 €/day is 100 days, not 50.
    assert_equal today + 100, payback.projected_date
  end

  test "a plant that saves nothing at all cannot be projected" do
    today = Date.new(2026, 9, 1)
    dated = (0...100).map { |i| [ today - 99 + i, 0.0 ] }

    assert_nil Payback.new(acquisition_cost_eur: 100.0, daily_savings: dated, today: today).projected_date
  end
end
