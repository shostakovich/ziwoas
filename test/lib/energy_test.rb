require "test_helper"

class EnergyTest < ActiveSupport::TestCase
  cover "Energy*"

  test "wh takes the canonical unit and coerces to float" do
    assert_in_delta 250.0, Energy.wh(250).wh
    assert_in_delta 703.4993, Energy.wh(703.4993).wh
  end

  test "kwh constructor scales up to watt-hours" do
    assert_in_delta 1_500.0, Energy.kwh(1.5).wh
  end

  test "zero is the empty amount" do
    assert_in_delta 0.0, Energy.zero.wh
    assert_predicate Energy.zero, :zero?
    assert_not_predicate Energy.wh(1.0), :zero?
  end

  test "sum adds up watt-hours without rounding in between" do
    seven = Array.new(7) { Energy.wh(100.4999) }

    assert_in_delta 703.4993, Energy.sum(seven).wh, 1e-9
    assert_in_delta 0.0, Energy.sum([]).wh
  end

  test "kwh converts without rounding" do
    assert_in_delta 0.7034993, Energy.wh(703.4993).kwh, 1e-12
    assert_in_delta 0.0001, Energy.wh(0.1).kwh, 1e-12
  end

  test "addition and subtraction stay in watt-hours" do
    assert_in_delta 300.0, (Energy.wh(100.0) + Energy.wh(200.0)).wh
    assert_in_delta(-100.0, (Energy.wh(100.0) - Energy.wh(200.0)).wh)
  end

  test "division splits the amount" do
    assert_in_delta 250.0, (Energy.wh(1_000.0) / 4).wh
  end

  test "negative? reports the sign" do
    assert_predicate Energy.wh(-1.0), :negative?
    assert_not_predicate Energy.zero, :negative?
    assert_not_predicate Energy.wh(1.0), :negative?
  end

  test "ratio_to divides two amounts and answers zero for an empty denominator" do
    assert_in_delta 0.6, Energy.wh(600.0).ratio_to(Energy.wh(1_000.0))
    assert_equal 0.0, Energy.wh(600.0).ratio_to(Energy.zero)
  end

  test "two amounts of the same size are equal" do
    assert_equal Energy.wh(500.0), Energy.wh(500)
    assert_not_equal Energy.wh(500.0), Energy.wh(500.1)
  end
end
