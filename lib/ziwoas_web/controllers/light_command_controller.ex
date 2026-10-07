defmodule ZiwoasWeb.LightCommandController do
  @moduledoc """
  The lamp commands (Rails' `LightsController#command`): `POST /lights/:light_key/command`
  with `command` and its parameters. Turning streams the hero and the Schalten tile
  back (Turbo applies whichever target the page has), a zone its buttons and the
  toast; brightness, colour, white and scenes answer 204. 503 when the broker is
  unreachable, 422 for anything the contract refuses.
  """
  use ZiwoasWeb, :controller

  alias Ziwoas.Lights
  alias Ziwoas.Lights.Commands
  alias ZiwoasWeb.{LightsComponents, TurboStream}

  plug ZiwoasWeb.Owned, task: :lights

  def create(conn, params) do
    with light when not is_nil(light) <- Lights.get_by_key(params["light_key"]),
         true <- Commands.command?(params["command"]) do
      case Commands.run(light, params["command"], params) do
        {:ok, :power} -> respond_power(conn, light)
        {:ok, {:zones, keys, toast}} -> respond_zones(conn, light, keys, toast)
        # Rails drops the content type of a 204.
        {:ok, :no_content} -> send_resp(conn, :no_content, "")
        {:error, :commander} -> TurboStream.head(conn, :service_unavailable)
        {:error, :invalid} -> TurboStream.head(conn, :unprocessable_entity)
      end
    else
      nil -> TurboStream.head(conn, :not_found)
      false -> TurboStream.head(conn, :unprocessable_entity)
    end
  end

  defp respond_power(conn, light) do
    snapshot = Lights.snapshot(light)

    TurboStream.send(conn, [
      {"replace", "light_power",
       TurboStream.component(&LightsComponents.power/1, %{snapshot: snapshot})},
      {"replace", "light_card_#{light.key}",
       TurboStream.component(&LightsComponents.light_card/1, %{snapshot: snapshot})}
    ])
  end

  defp respond_zones(conn, light, keys, toast) do
    zones = light |> Lights.snapshot() |> Lights.zones() |> Map.new(&{&1.key, &1})

    streams =
      for key <- keys do
        {"replace", "zone_#{key}",
         TurboStream.component(&LightsComponents.zone/1, %{zone: zones[key], light_key: light.key})}
      end

    toast_stream =
      if toast,
        do: [
          {"replace", "light_toast",
           TurboStream.component(
             &LightsComponents.toast/1,
             LightsComponents.toast_assigns(light, toast)
           )}
        ],
        else: []

    TurboStream.send(conn, streams ++ toast_stream)
  end
end
