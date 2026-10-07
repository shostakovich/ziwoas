defmodule ZiwoasWeb.LightEvents do
  @moduledoc """
  The lamp controls as a LiveView event (`"light_command"`): the forms that post to
  `/lights/:key/command` on a Rails page submit their fields, plus `light_key`, to
  the LiveView serving the page. Same commands as `ZiwoasWeb.LightCommandController`,
  only as owner of `lights`.
  """
  alias Ziwoas.{Lights, Ownership}
  alias Ziwoas.Lights.Commands

  @spec run(map) ::
          {:ok, Lights.Light.t(), Commands.result()}
          | {:error, :not_owner | :not_found | :invalid | :commander}
  def run(params) do
    with :ok <- owner(),
         {:ok, light} <- light(params["light_key"]),
         true <- Commands.command?(params["command"]) || {:error, :invalid},
         {:ok, result} <- Commands.run(light, params["command"], params) do
      {:ok, light, result}
    end
  end

  defp owner, do: if(Ownership.acting?(:lights), do: :ok, else: {:error, :not_owner})

  defp light(key) when is_binary(key) do
    case Lights.get_by_key(key) do
      nil -> {:error, :not_found}
      light -> {:ok, light}
    end
  end

  defp light(_key), do: {:error, :not_found}
end
