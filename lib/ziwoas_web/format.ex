defmodule ZiwoasWeb.Format do
  @moduledoc "Mirrors `assets/js/lib/format.js`: decimal comma, true minus (U+2212), rounding half away from zero."

  @minus "−"
  @missing "—"

  @type value :: number | Decimal.t() | :nan | nil

  @spec number(value, keyword) :: String.t()
  def number(value, opts \\ []) do
    value |> digits(Keyword.get(opts, :precision, 0)) |> with_unit(opts[:unit])
  end

  @doc "A flow that rounds to zero carries no direction."
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

  @spec eur(value) :: String.t()
  def eur(nil), do: @missing
  def eur(value), do: number(value, precision: 2, unit: "€")

  @spec date(Date.t() | DateTime.t() | NaiveDateTime.t()) :: String.t()
  def date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  @spec day_month(Date.t() | DateTime.t() | NaiveDateTime.t()) :: String.t()
  def day_month(date), do: Calendar.strftime(date, "%d.%m.")

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
