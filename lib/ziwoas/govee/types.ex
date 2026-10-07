defmodule Ziwoas.Govee.Types do
  @moduledoc """
  The lenient primitives of the Govee wire protocol (LAN replies, Platform API
  states): integers in their usual string forms, with range constraints. Each
  returns `{:ok, value}` or `:error`.
  """

  @doc "An integer, a float (truncated) or a decimal string (surrounding whitespace, `_` separators)."
  def integer(value) when is_integer(value), do: {:ok, value}
  def integer(value) when is_float(value), do: {:ok, trunc(value)}

  def integer(value) when is_binary(value) do
    case Regex.run(~r/\A[ \t\n\v\f\r]*([+-]?\d+(?:_\d+)*)[ \t\n\v\f\r]*\z/, value) do
      [_, digits] -> {:ok, digits |> String.replace("_", "") |> String.to_integer()}
      nil -> :error
    end
  end

  def integer(_), do: :error

  def brightness(value), do: ranged(integer(value), 0, 100)
  def kelvin(value), do: ranged(integer(value), 0, nil)
  def rgb_component(value), do: ranged(integer(value), 0, 255)

  @doc "A string, never coerced."
  def string(value) when is_binary(value), do: {:ok, value}
  def string(_), do: :error

  defp ranged({:ok, value}, min, max) when value >= min and (is_nil(max) or value <= max),
    do: {:ok, value}

  defp ranged(_, _min, _max), do: :error
end
