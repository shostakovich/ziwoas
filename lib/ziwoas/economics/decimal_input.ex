defmodule Ziwoas.Economics.DecimalInput do
  @moduledoc false

  @spec normalize(map, String.t()) :: map
  def normalize(%{} = attrs, key) do
    case attrs do
      %{^key => value} when is_binary(value) -> %{attrs | key => String.replace(value, ",", ".")}
      _ -> attrs
    end
  end

  # Decimal raises when rounding needs more digits than its precision; values that large fail
  # the column bound anyway, so they stay unrounded for that check to refuse.
  @spec round_below(Decimal.t(), non_neg_integer, pos_integer) :: Decimal.t()
  def round_below(value, scale, limit) do
    if Decimal.lt?(Decimal.abs(value), limit), do: Decimal.round(value, scale), else: value
  end
end
