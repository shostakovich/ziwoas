defmodule ZiwoasWeb.LightEvents do
  @moduledoc """
  The lamp controls' `"light_command"` event, shared by `ZiwoasWeb.SwitchesLive`
  (the tile) and `ZiwoasWeb.LightLive`: `light_key`, `command` and the command's
  parameters, run through `Ziwoas.Lights.command/3`.
  """
  alias Ziwoas.Lights

  @failed "Lampe nicht erreichbar"

  @doc "The flash for a command the bridge did not take."
  def failed_message, do: @failed

  @spec run(map) ::
          {:ok, Lights.Light.t(), Lights.Commands.result()}
          | {:error, :not_found | :invalid | :unreachable}
  def run(params) do
    with {:ok, light} <- light(params["light_key"]),
         true <- Lights.command?(params["command"]) || {:error, :invalid},
         {:ok, result} <- Lights.command(light, params["command"], params) do
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
