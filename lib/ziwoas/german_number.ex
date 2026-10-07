defmodule Ziwoas.GermanNumber do
  @moduledoc """
  Numbers as German UI text: a decimal comma, dots between thousands and a
  true minus (U+2212), which is as wide as a plus in tabular figures. The twin
  of formatNumber and formatFlow in app/javascript/lib/format.js.

  Takes integers, floats, `Decimal`s, `:nan` and nil; NaN and nil read as a dash.
  """
  alias Ziwoas.RubyNumeric

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
    magnitude = value |> magnitude() |> digits(Keyword.get(opts, :precision, 0))

    if magnitude =~ ~r/[1-9]/ do
      direction =
        if positive?(value),
          do: Keyword.fetch!(opts, :positive),
          else: Keyword.fetch!(opts, :negative)

      "#{direction} #{with_unit(magnitude, unit)}"
    else
      with_unit(magnitude, unit)
    end
  end

  defp digits(value, precision) do
    case to_float(value) do
      nil ->
        @missing

      number ->
        rounded = RubyNumeric.round(number, precision)
        {integer, fraction} = split(rounded, precision)
        grouped = Regex.replace(~r/\B(?=(\d{3})+\z)/, integer, ".")
        # -0.0 is not negative: a value that rounds to zero carries no sign.
        sign = if rounded < 0, do: @minus, else: ""
        sign <> Enum.join(Enum.reject([grouped, fraction], &is_nil/1), ",")
    end
  end

  defp split(rounded, 0), do: {Integer.to_string(abs(rounded)), nil}

  defp split(rounded, precision) do
    [integer, fraction] =
      rounded |> abs() |> RubyNumeric.format_fixed(precision) |> String.split(".")

    {integer, fraction}
  end

  defp to_float(nil), do: nil
  defp to_float(:nan), do: nil
  defp to_float(%Decimal{coef: :NaN}), do: nil
  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(value) when is_number(value), do: :erlang.float(value)

  defp magnitude(%Decimal{} = value), do: Decimal.abs(value)
  defp magnitude(value) when is_number(value), do: abs(value)
  defp magnitude(value), do: value

  defp positive?(%Decimal{} = value), do: Decimal.gt?(value, 0)
  defp positive?(value), do: value > 0

  defp with_unit(text, nil), do: text
  defp with_unit(text, unit), do: "#{text} #{unit}"
end
