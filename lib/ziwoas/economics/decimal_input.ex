defmodule Ziwoas.Economics.DecimalInput do
  @moduledoc "Amounts as typed on a German keyboard: `12,50` reads as `12.50`."

  @spec normalize(map, String.t()) :: map
  def normalize(%{} = attrs, key) do
    case attrs do
      %{^key => value} when is_binary(value) -> %{attrs | key => String.replace(value, ",", ".")}
      _ -> attrs
    end
  end
end
