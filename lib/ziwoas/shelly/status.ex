defmodule Ziwoas.Shelly.Status do
  @moduledoc false

  @type t :: map
  @spec replace(map) :: t
  def replace(full) when is_map(full), do: full

  # A NotifyStatus delta carries only the changed keys; `null` marks a key that is gone.
  @spec merge(t, map) :: t
  def merge(status, delta) when is_map(delta) do
    Enum.reduce(delta, status, fn
      {key, nil}, acc -> Map.delete(acc, key)
      {key, value}, acc when is_map(value) -> Map.put(acc, key, merge(sub(acc, key), value))
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  def merge(status, _delta), do: status

  defp sub(status, key) do
    case status do
      %{^key => value} when is_map(value) -> value
      _ -> %{}
    end
  end

  @spec reading(t) :: {:ok, Ziwoas.Plugs.Ingest.reading()} | {:error, :incomplete_status}
  def reading(%{"apower" => apower, "aenergy" => %{"total" => total}} = status)
      when is_number(apower) and is_number(total),
      do: {:ok, %{apower_w: apower * 1.0, aenergy_wh: total * 1.0, output: output(status)}}

  def reading(_status), do: {:error, :incomplete_status}

  defp output(%{"output" => output}) when is_boolean(output), do: output
  defp output(_status), do: nil
end
