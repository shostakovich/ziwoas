defmodule Ziwoas.Economics.DecimalInput do
  @moduledoc false

  @spec normalize(map, String.t()) :: map
  def normalize(%{} = attrs, key) do
    case attrs do
      %{^key => value} when is_binary(value) -> %{attrs | key => String.replace(value, ",", ".")}
      _ -> attrs
    end
  end
end
