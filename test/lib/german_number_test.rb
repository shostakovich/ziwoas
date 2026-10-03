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

  test "writes a missing value as zero" do
    assert_equal "0", GermanNumber.format(nil)
    assert_equal "0,0", GermanNumber.format(nil, precision: 1)
  end
end
