defmodule Ziwoas.Economics.DecimalColumn do
  @moduledoc """
  A DECIMAL(precision, scale) value read the way ActiveRecord reads it from
  SQLite, followed by Ruby's `to_f`.

  NUMERIC affinity stores `12.35` as REAL and `12.00` as INTEGER. An INTEGER is
  taken as is; a REAL goes through `Float#round(scale)`, `BigDecimal(value,
  precision)` (correctly rounded to `precision` significant digits) and
  `BigDecimal#round(scale)`. A SUM of 199999999.98 over DECIMAL(10,2) therefore
  reads as 200000000.0.
  """
  alias Ziwoas.RubyNumeric

  # ActiveModel caps the float precision at Float::DIG + 1.
  @max_float_precision 16

  @spec to_float(integer | float, pos_integer, non_neg_integer) :: float
  def to_float(value, _precision, _scale) when is_integer(value), do: :erlang.float(value)

  def to_float(value, precision, scale) when is_float(value) do
    value
    |> RubyNumeric.round(scale)
    |> significant_digits(min(precision, @max_float_precision))
    |> Decimal.round(scale, :half_up)
    |> Decimal.to_float()
  end

  @doc """
  What ActiveRecord writes for a Float assigned to the column
  (`ActiveModel::Type::Decimal#cast`, then `to_f` on the way into SQLite):
  the same rounding as reading, a negative zero kept.
  """
  @spec cast(float, pos_integer, non_neg_integer) :: float
  def cast(value, _precision, _scale) when value == 0.0, do: value
  def cast(value, precision, scale) when is_float(value), do: to_float(value, precision, scale)

  defp significant_digits(value, _digits) when value == 0.0, do: Decimal.new(0)

  defp significant_digits(value, digits) do
    exact = exact_decimal(value)
    adjusted = length(Integer.digits(exact.coef)) + exact.exp - 1
    Decimal.round(exact, digits - 1 - adjusted, :half_even)
  end

  defp exact_decimal(value) do
    {numerator, denominator} = RubyNumeric.exact(value)
    sign = if numerator < 0, do: -1, else: 1
    # denominator = 2^k, so numerator / 2^k = numerator * 5^k / 10^k exactly.
    k = length(Integer.digits(denominator, 2)) - 1
    Decimal.new(sign, abs(numerator) * 5 ** k, -k)
  end
end
