defmodule Ziwoas.Lights.Power do
  @moduledoc false
  alias Ziwoas.Govee.Bridge
  alias Ziwoas.Lights.Light
  alias Ziwoas.Plugs
  alias Ziwoas.Plugs.Plug

  @type t :: :powered | {:unpowered, Plug.t()} | {:silent, Plug.t()}

  @spec lamp_plug?(Plug.t()) :: boolean
  def lamp_plug?(%Plug{switchable: true, driver: :shelly}), do: true
  def lamp_plug?(%Plug{}), do: false

  @doc "A stored plug that is no longer a lamp plug counts as none."
  @spec plug(Light.t(), [Plug.t()]) :: Plug.t() | nil
  def plug(%Light{shelly_plug_id: nil}, _plugs), do: nil

  def plug(%Light{shelly_plug_id: id}, plugs),
    do: Enum.find(plugs, &(&1.id == id and lamp_plug?(&1)))

  @spec of(Light.t(), [Plug.t()]) :: t
  def of(light, plugs) do
    case plug(light, plugs) do
      nil -> :powered
      plug -> of_plug(light, plug)
    end
  end

  defp of_plug(light, plug) do
    cond do
      relay_off?(Plugs.states([plug.id])[plug.id]) -> {:unpowered, plug}
      Bridge.silent?(light.key) -> {:silent, plug}
      true -> :powered
    end
  end

  @spec unpowered_keys([Light.t()], [Plug.t()]) :: MapSet.t(String.t())
  def unpowered_keys(lights, plugs) do
    by_key = for light <- lights, plug = plug(light, plugs), into: %{}, do: {light.key, plug.id}
    states = by_key |> Map.values() |> Enum.uniq() |> Plugs.states()

    for {key, plug_id} <- by_key, relay_off?(states[plug_id]), into: MapSet.new(), do: key
  end

  defp relay_off?(%Plugs.State{output: false}), do: true
  defp relay_off?(_state), do: false
end
