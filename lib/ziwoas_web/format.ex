defmodule ZiwoasWeb.Format do
  @moduledoc """
  Numbers, money, dates and clock times as German UI text. Imported into every
  component and LiveView.

  Numbers take a decimal comma, dots between thousands and a true minus
  (U+2212), which is as wide as a plus in tabular figures: the twin of
  `formatNumber` and `formatFlow` in `assets/js/lib/format.js`. They accept
  integers, floats, `Decimal`s, `:nan` and nil; NaN and nil read as a dash.
  Rounding is half away from zero on the shortest decimal form of a float, like
  `Intl.NumberFormat`: 2.675 reads as 2,68.
  """

  @minus "−"
  @missing "—"

  @type value :: number | Decimal.t() | :nan | nil

  @doc """
  A number with `precision:` decimals (default 0) and an optional `unit:`.

      iex> ZiwoasWeb.Format.number(1234.5, precision: 2, unit: "kWh")
      "1.234,50 kWh"
  """
  @spec number(value, keyword) :: String.t()
  def number(value, opts \\ []) do
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

  @doc "Euros with cents; an unknown amount is a dash without the sign."
  @spec eur(value) :: String.t()
  def eur(nil), do: @missing
  def eur(value), do: number(value, precision: 2, unit: "€")

  @doc "A date as `07.10.2026`."
  @spec date(Date.t() | DateTime.t() | NaiveDateTime.t()) :: String.t()
  def date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  @doc "A date without its year, `07.10.`."
  @spec day_month(Date.t() | DateTime.t() | NaiveDateTime.t()) :: String.t()
  def day_month(date), do: Calendar.strftime(date, "%d.%m.")

  @doc "An instant as the wall-clock time `HH:MM` in `zone`."
  @spec clock(DateTime.t(), String.t()) :: String.t()
  def clock(%DateTime{} = time, zone),
    do: time |> DateTime.shift_zone!(zone) |> Calendar.strftime("%H:%M")

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
