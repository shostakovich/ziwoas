defmodule ZiwoasWeb.LightController do
  @moduledoc """
  A lamp's settings (Rails' `LightsController#edit`/`#update`): name and Shelly
  plug. Turbo gets the settings sheet as a stream into `#light_settings`, a
  plain request the edit page; a saved form goes back to the lamp's page.
  """
  use ZiwoasWeb, :controller

  import ZiwoasWeb.LightsComponents, only: [settings_sheet: 1]

  alias Ziwoas.{Config, Lights}
  alias Ziwoas.Lights.Light
  alias ZiwoasWeb.TurboStream

  plug ZiwoasWeb.Owned, [task: :light_settings] when action == :update
  plug :fetch_light

  def edit(conn, _params), do: respond(conn, 200, conn.assigns.light, [])

  def update(conn, params) do
    case light_params(params) do
      nil ->
        conn |> put_resp_content_type("text/html") |> send_resp(:bad_request, "")

      attrs ->
        case Lights.update_settings(conn.assigns.light, attrs) do
          {:ok, light} ->
            conn
            |> put_flash(:notice, "Lampe aktualisiert.")
            |> redirect(to: ~p"/lights/#{light.key}")

          {:error, changeset} ->
            respond(
              conn,
              422,
              Ecto.Changeset.apply_changes(changeset),
              Light.full_messages(changeset)
            )
        end
    end
  end

  defp respond(conn, status, light, errors) do
    plugs = Config.app_config().plugs

    if TurboStream.requested?(conn) do
      TurboStream.send(
        conn,
        [
          {"update", "light_settings",
           TurboStream.component(&settings_sheet/1, %{light: light, plugs: plugs, errors: errors})}
        ],
        status
      )
    else
      conn
      |> put_status(status)
      |> assign(:page_title, "Lampe bearbeiten")
      |> render(:edit,
        current_path: conn.request_path,
        light: light,
        plugs: plugs,
        errors: errors
      )
    end
  end

  defp fetch_light(conn, _opts) do
    case Lights.get_by_key(conn.params["key"]) do
      nil -> raise ZiwoasWeb.NotFoundError
      light -> assign(conn, :light, light)
    end
  end

  # `params.require(:light).permit(:name, :shelly_plug_id)`: nil where Rails
  # answers 400 (no light, or an empty one); only the two keys, only scalars.
  defp light_params(%{"light" => %{} = given}) when map_size(given) > 0 do
    for {key, value} <- given,
        key in ~w[name shelly_plug_id],
        is_nil(value) or is_binary(value),
        into: %{},
        do: {key, value}
  end

  defp light_params(_params), do: nil
end
