defmodule Ziwoas.Govee.Types do
  @moduledoc """
  The liberal wire primitives of the Govee messages and the lamp events: booleans
  and integers in their usual string forms, with range constraints. Each returns
  `{:ok, value}` or `:error`.
  """

  @true_words ~w[1 on On ON t true True TRUE T y yes Yes YES Y]
  @false_words ~w[0 off Off OFF f false False FALSE F n no No NO N]

  @doc "true/false, 1/0 and their word forms (on/off, yes/no, t/f, y/n)."
  def bool(value) when is_boolean(value), do: {:ok, value}
  def bool(1), do: {:ok, true}
  def bool(0), do: {:ok, false}
  def bool(value) when value in @true_words, do: {:ok, true}
  def bool(value) when value in @false_words, do: {:ok, false}
  def bool(_), do: :error

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

  @doc "A non-empty string, never coerced."
  def name(value) when is_binary(value) and value != "", do: {:ok, value}
  def name(_), do: :error

  @doc "A string, never coerced."
  def string(value) when is_binary(value), do: {:ok, value}
  def string(_), do: :error

  @doc "An integer or nil, never coerced."
  def optional_integer(value) when is_integer(value) or is_nil(value), do: {:ok, value}
  def optional_integer(_), do: :error

  defp ranged({:ok, value}, min, max) when value >= min and (is_nil(max) or value <= max),
    do: {:ok, value}

  defp ranged(_, _min, _max), do: :error

  @doc "Applies a coercion to every element; `:error` if one fails."
  def list_of(values, fun) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, coerced} -> {:cont, {:ok, [coerced | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      :error -> :error
    end
  end

  def list_of(_values, _fun), do: :error
end
