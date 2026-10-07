defmodule Ziwoas.Economics.DecimalColumnTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Economics.DecimalColumn

  # Expected values from ActiveModel::Type::Decimal#deserialize(...).to_f (Rails 8.1).
  test "a REAL rounds to the scale with Ruby's Float#round" do
    assert DecimalColumn.to_float(12.345, 10, 2) === 12.35
    assert DecimalColumn.to_float(1.005, 10, 2) === 1.01
    assert DecimalColumn.to_float(0.1 + 0.2, 10, 2) === 0.3
    assert DecimalColumn.to_float(0.123455, 8, 5) === 0.12346
    assert DecimalColumn.to_float(1.0e-5, 8, 5) === 1.0e-5
  end

  test "a REAL keeps only `precision` significant digits" do
    assert DecimalColumn.to_float(199_999_999.98, 10, 2) === 200_000_000.0
  end

  test "an INTEGER is taken as is, whatever the precision" do
    assert DecimalColumn.to_float(1_234_567_890_123, 10, 2) === 1_234_567_890_123.0
  end
end
