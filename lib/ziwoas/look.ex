defmodule Ziwoas.Look do
  @moduledoc """
  The page look (Rails' `Look`): plain felt-css ("clean") or the felt texture
  ("felt"), kept in the unsigned `look` cookie both apps read.
  """
  @names ~w[clean felt]
  @default "clean"
  @cookie "look"

  # The browser chrome follows the page background (felt-css --felt-body-bg).
  @theme_colors %{
    "clean" => %{light: "#f6f7f9", dark: "#212529"},
    "felt" => %{light: "#dbcdb7", dark: "#242220"}
  }

  def cookie, do: @cookie

  @spec valid?(term) :: boolean
  def valid?(value), do: value in @names

  @doc "The look a cookie value names; anything else is the default."
  @spec named(term) :: String.t()
  def named(value), do: if(valid?(value), do: value, else: @default)

  @spec theme_colors(String.t()) :: %{light: String.t(), dark: String.t()}
  def theme_colors(look), do: Map.fetch!(@theme_colors, look)
end
