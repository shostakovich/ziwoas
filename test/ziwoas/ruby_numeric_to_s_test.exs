defmodule Ziwoas.RubyNumericToSTest do
  # Float#to_s and format("%g") as Ruby 4 prints them (checked against `ruby -e`).
  use ExUnit.Case, async: true

  alias Ziwoas.RubyNumeric

  @cases [
    {100.0, "100.0", "100"},
    {0.001, "0.001", "0.001"},
    {0.0001, "0.0001", "0.0001"},
    {1.0e-5, "1.0e-05", "1e-05"},
    {1.0e16, "1.0e+16", "1e+16"},
    {1.0e15, "1.0e+15", "1e+15"},
    {1.0e14, "100000000000000.0", "1e+14"},
    {123_456_789_012_345_680.0, "1.2345678901234568e+17", "1.23457e+17"},
    {12.3, "12.3", "12.3"},
    {-0.0, "-0.0", "-0"},
    {0.0, "0.0", "0"},
    {3.125, "3.125", "3.125"},
    {53.125, "53.125", "53.125"},
    {1_234_567.0, "1234567.0", "1.23457e+06"},
    {99.95, "99.95", "99.95"},
    {2.5e-5, "2.5e-05", "2.5e-05"},
    {123.456789, "123.456789", "123.457"},
    {0.00012, "0.00012", "0.00012"},
    {9_999_999_999_999_998.0, "9.999999999999998e+15", "1e+16"},
    {123_456_789_012_345.0, "123456789012345.0", "1.23457e+14"}
  ]

  test "Float#to_s" do
    for {value, to_s, _g} <- @cases, do: assert(RubyNumeric.to_s(value) == to_s, inspect(value))
    assert RubyNumeric.to_s(42) == "42"
  end

  test "format('%g')" do
    for {value, _to_s, g} <- @cases, do: assert(RubyNumeric.format_g(value) == g, inspect(value))
    assert RubyNumeric.format_g(50) == "50"
  end
end
