defmodule Ziwoas.Shelly.Status do
  @moduledoc """
  A Shelly's `switch:0` status as the connection keeps it: a full status
  (`NotifyFullStatus`, `Shelly.GetStatus`) replaces it, a `NotifyStatus` delta is
  merged into it (only the changed keys, `null` for a key that is gone).
  """

  @type t :: map

  @doc "The status after a full status; anything but a map leaves none."
  @spec replace(map) :: t
  def replace(full) when is_map(full), do: full
  def replace(_full), do: %{}

  @doc "The status with `delta` merged in, nested maps (`aenergy`) key by key."
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

  @doc "The plug reading the status carries: watts and counter as numbers, the relay if a boolean."
  @spec reading(t) :: {:ok, Ziwoas.Plugs.Ingest.reading()} | {:error, :incomplete_status}
  def reading(%{"apower" => apower, "aenergy" => %{"total" => total}} = status)
      when is_number(apower) and is_number(total),
      do: {:ok, %{apower_w: apower * 1.0, aenergy_wh: total * 1.0, output: output(status)}}

  def reading(_status), do: {:error, :incomplete_status}

  defp output(%{"output" => output}) when is_boolean(output), do: output
  defp output(_status), do: nil
end
