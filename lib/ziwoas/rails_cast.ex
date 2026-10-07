defmodule Ziwoas.RailsCast do
  @moduledoc """
  ActiveModel's attribute casts, for values from outside (a JSON API) that Rails
  assigns to a column: what Rails would store. A Float column takes an Integer
  as Float, an Integer column truncates a Float, blank strings are nil.
  `test/vectors/weather_sync.json` pins them.
  """
  alias Ziwoas.RubyNumeric

  @spec float(term) :: float | nil
  def float(nil), do: nil
  def float(value) when is_float(value), do: value
  def float(value) when is_integer(value), do: :erlang.float(value)
  def float(true), do: 1.0
  def float(false), do: 0.0

  def float(value) when is_binary(value),
    do: if(blank?(value), do: nil, else: RubyNumeric.to_f(value))

  @spec integer(term) :: integer | nil
  def integer(nil), do: nil
  def integer(value) when is_integer(value), do: value
  def integer(value) when is_float(value), do: trunc(value)
  def integer(true), do: 1
  def integer(false), do: 0

  def integer(value) when is_binary(value),
    do: if(blank?(value), do: nil, else: RubyNumeric.to_i(value))

  @spec string(term) :: String.t() | nil
  def string(nil), do: nil
  def string(value) when is_binary(value), do: value
  def string(true), do: "t"
  def string(false), do: "f"
  def string(value) when is_number(value), do: RubyNumeric.to_s(value)

  defp blank?(value), do: String.trim(value) == ""
end
