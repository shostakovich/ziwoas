require "test_helper"

class GermanNumberTest < ActiveSupport::TestCase
  cover "GermanNumber*"

  test "writes a decimal comma and a dot between thousands" do
    assert_equal "1.234.567,89", GermanNumber.format(1_234_567.891, precision: 2)
    assert_equal "999", GermanNumber.format(999)
    assert_equal "1.000", GermanNumber.format(1000)
  end

  test "rounds to the precision it is asked for, whole numbers by default" do
    assert_equal "3", GermanNumber.format(2.5)
    assert_equal "2,7", GermanNumber.format(2.66, precision: 1)
    assert_equal "0,00", GermanNumber.format(0, precision: 2)
  end

  test "puts a true minus sign in front of a negative value" do
    assert_equal "−2,97", GermanNumber.format(-2.97, precision: 2)
    assert_equal "−1.992", GermanNumber.format(-1992)
  end

  test "drops the sign where a small negative value rounds to zero" do
    assert_equal "0,00", GermanNumber.format(-0.001, precision: 2)
    assert_equal "0", GermanNumber.format(-0.4)
  end

  test "takes integers, decimals and floats alike" do
    assert_equal "12,50", GermanNumber.format(BigDecimal("12.5"), precision: 2)
    assert_equal "7,0", GermanNumber.format(7, precision: 1)
  end

  test "writes a missing value as a dash, not as a measured zero" do
    assert_equal "—", GermanNumber.format(nil)
    assert_equal "—", GermanNumber.format(nil, precision: 1)
    assert_equal "—", GermanNumber.format(Float::NAN, precision: 2)
    assert_equal "—", GermanNumber.format(BigDecimal("NaN"))
  end

  test "puts the unit after a space, behind a missing value too" do
    assert_equal "1.980 W", GermanNumber.format(1980.4, unit: "W")
    assert_equal "−0,25 kWh", GermanNumber.format(-0.25, precision: 2, unit: "kWh")
    assert_equal "0 W", GermanNumber.format(-0.4, unit: "W")
    assert_equal "— W", GermanNumber.format(nil, unit: "W")
    assert_equal "— %", GermanNumber.format(Float::NAN, precision: 1, unit: "%")
  end

  test "a flow says its direction in words instead of a sign" do
    words = { positive: "lädt", negative: "entlädt" }

    assert_equal "lädt 180 W", GermanNumber.flow(180.2, **words)
    assert_equal "entlädt 1.941 W", GermanNumber.flow(-1941, **words)
    assert_equal "lädt 0,25 kWh", GermanNumber.flow(0.25, **words, unit: "kWh", precision: 2)
    assert_equal "entlädt 1 W", GermanNumber.flow(-0.5, **words)
  end

  test "a flow that rounds to zero is no flow, and a missing one a dash" do
    words = { positive: "liefert", negative: "zieht" }

    assert_equal "0 W", GermanNumber.flow(-0.3, **words)
    assert_equal "0 W", GermanNumber.flow(0.49, **words)
    assert_equal "0,00 kWh", GermanNumber.flow(0.004, **words, unit: "kWh", precision: 2)
    assert_equal "— W", GermanNumber.flow(nil, **words)
    assert_equal "— W", GermanNumber.flow(Float::NAN, **words)
  end
end
