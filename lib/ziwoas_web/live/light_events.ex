defmodule ZiwoasWeb.LightEvents do
  @moduledoc """
  The lamp controls' `"light_command"` event, shared by `ZiwoasWeb.SwitchesLive`
  (the tile) and `ZiwoasWeb.LightLive`: `light_key`, `command` and the command's
  parameters, run through `Ziwoas.Lights.Commands`.
  """
  alias Ziwoas.Lights
  alias Ziwoas.Lights.Commands

  @failed "Lampe nicht erreichbar — MQTT-Broker nicht erreichbar"

  @doc "The flash for a command the broker did not take."
  def failed_message, do: @failed

  @spec run(map) ::
          {:ok, Lights.Light.t(), Commands.result()}
          | {:error, :not_found | :invalid | :commander}
  def run(params) do
    with {:ok, light} <- light(params["light_key"]),
         true <- Commands.command?(params["command"]) || {:error, :invalid},
         {:ok, result} <- Commands.run(light, params["command"], params) do
      {:ok, light, result}
    end
  end

  defp light(key) when is_binary(key) do
    case Lights.get_by_key(key) do
      nil -> {:error, :not_found}
      light -> {:ok, light}
    end
  end

  defp light(_key), do: {:error, :not_found}
end
