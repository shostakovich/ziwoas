defmodule Ziwoas.Economics.PaybackTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Economics.Payback

  @today ~D[2026-10-06]

  # `count` days ending today, each saving `eur`.
  defp days(count, eur, until \\ @today),
    do: for(offset <- (count - 1)..0//-1, do: {Date.add(until, -offset), eur})

  test "the savings are the days on record, summed" do
    payback = Payback.new(1_000, days(10, 1.5), @today)

    assert Payback.saved_eur(payback) == 15.0
    assert Payback.data_start(payback) == Date.add(@today, -9)
  end

  test "without days nothing is saved and there is no data start" do
    payback = Payback.new(1_000, [], @today)

    assert Payback.saved_eur(payback) == 0.0
    assert Payback.data_start(payback) == nil
    assert Payback.covered_ratio(payback) == 0.0
    assert Payback.projected_date(payback) == nil
  end

  test "the days are taken in date order, whatever order they come in" do
    payback = Payback.new(10, [{~D[2026-03-02], 6.0}, {~D[2026-03-01], 5.0}], @today)

    assert Payback.data_start(payback) == ~D[2026-03-01]
    assert Payback.reached_on(payback) == ~D[2026-03-02]
  end

  describe "the covered share" do
    test "is the savings against the cost, capped at all of it" do
      assert Payback.covered_ratio(Payback.new(200, days(10, 5.0), @today)) == 0.25
      assert Payback.covered_ratio(Payback.new(20, days(10, 5.0), @today)) == 1.0
    end

    test "is unknown without a cost, and so is everything after it" do
      for cost <- [0, -150.0] do
        payback = Payback.new(cost, days(200, 5.0), @today)

        refute Payback.costed?(payback)
        assert Payback.covered_ratio(payback) == nil
        refute Payback.reached?(payback)
        assert Payback.reached_on(payback) == nil
        assert Payback.projected_date(payback) == nil
      end
    end
  end

  describe "reaching the cost" do
    test "names the first day the running total got there" do
      payback = Payback.new(10, days(5, 4.0), @today)

      assert Payback.reached?(payback)
      assert Payback.reached_on(payback) == Date.add(@today, -2)
    end

    test "reaching it exactly counts" do
      assert Payback.reached_on(Payback.new(8, days(5, 4.0), @today)) == Date.add(@today, -3)
    end

    test "is not reached a cent short" do
      payback = Payback.new(20.01, days(5, 4.0), @today)

      refute Payback.reached?(payback)
      assert Payback.reached_on(payback) == nil
    end
  end

  describe "the projection" do
    test "extends the average day over what is still missing" do
      payback = Payback.new(1_000, days(100, 1.0), @today)

      assert Payback.projection_days(payback) == 100
      assert Payback.projected_date(payback) == Date.add(@today, 900)
    end

    test "rounds the days still missing up" do
      payback = Payback.new(100.25, days(90, 0.5), @today)

      assert Payback.projected_date(payback) == Date.add(@today, 111)
    end

    test "needs 90 days on record" do
      assert Payback.projected_date(Payback.new(1_000, days(89, 1.0), @today)) == nil
      assert Payback.projected_date(Payback.new(1_000, days(90, 1.0), @today))
    end

    test "averages the last year only, while the total counts every day" do
      older = days(35, 10.0, Date.add(@today, -365))
      payback = Payback.new(1_000, older ++ days(365, 1.0), @today)

      assert Payback.projection_days(payback) == 365
      assert Payback.saved_eur(payback) == 715.0
      assert Payback.projected_date(payback) == Date.add(@today, 285)
    end

    test "is not made when the days saved nothing, or once the cost is reached" do
      assert Payback.projected_date(Payback.new(1_000, days(120, 0.0), @today)) == nil
      assert Payback.projected_date(Payback.new(50, days(120, 1.0), @today)) == nil
    end
  end
end
