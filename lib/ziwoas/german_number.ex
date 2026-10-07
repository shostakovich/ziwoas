defmodule Ziwoas.GermanNumber do
  @moduledoc """
  Numbers as German UI text: a decimal comma, dots between thousands and a
  true minus (U+2212), which is as wide as a plus in tabular figures. The twin
  of formatNumber and formatFlow in assets/js/lib/format.js.

  Takes integers, floats, `Decimal`s, `:nan` and nil; NaN and nil read as a dash.
  Rounds half away from zero on the shortest decimal form of a float, like
  `Intl.NumberFormat`: 2.675 reads as 2,68.
  """

  @minus "−"
  @missing "—"

  @type value :: number | Decimal.t() | :nan | nil

  @spec format(value, keyword) :: String.t()
  def format(value, opts \\ []) do
    value |> digits(Keyword.get(opts, :precision, 0)) |> with_unit(opts[:unit])
  end

  @doc """
  A flow says its direction in words (`positive:`/`negative:`) instead of a
  sign. One that rounds to zero is no flow and carries no direction.
  """
  @spec flow(value, keyword) :: String.t()
  def flow(value, opts) do
    unit = Keyword.get(opts, :unit, "W")
    precision = Keyword.get(opts, :precision, 0)

    case to_decimal(value) do
      nil ->
        with_unit(@missing, unit)

      decimal ->
        magnitude = decimal |> Decimal.abs() |> digits(precision) |> with_unit(unit)

        cond do
          not (magnitude =~ ~r/[1-9]/) -> magnitude
          Decimal.positive?(decimal) -> "#{Keyword.fetch!(opts, :positive)} #{magnitude}"
          true -> "#{Keyword.fetch!(opts, :negative)} #{magnitude}"
        end
    end
  end

  defp digits(value, precision) do
    case to_decimal(value) do
      nil ->
        @missing

      decimal ->
        rounded = Decimal.round(decimal, precision, :half_up)

        [integer | fraction] =
          rounded |> Decimal.abs() |> Decimal.to_string(:normal) |> String.split(".")

        grouped = Regex.replace(~r/\B(?=(\d{3})+\z)/, integer, ".")
        # A value that rounds to zero carries no sign.
        sign = if Decimal.negative?(rounded) and not Decimal.eq?(rounded, 0), do: @minus, else: ""
        sign <> Enum.join([grouped | fraction], ",")
    end
  end

  defp to_decimal(nil), do: nil
  defp to_decimal(:nan), do: nil
  defp to_decimal(%Decimal{coef: coef}) when coef in [:NaN, :inf], do: nil
  defp to_decimal(%Decimal{} = value), do: value
  defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp with_unit(text, nil), do: text
  defp with_unit(text, unit), do: "#{text} #{unit}"
end
