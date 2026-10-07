defmodule ZiwoasWeb.Nav do
  @moduledoc """
  `on_mount` for every LiveView: the look and the request path the navigation
  marks as current.

  The look comes from the socket's connect params once connected (the browser
  may have switched it since the page was loaded), else from the session. The
  look toggle's `"set_look"` event is answered here for every page.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, get_connect_params: 1]

  alias ZiwoasWeb.Look

  def on_mount(:default, _params, session, socket) do
    socket =
      socket
      |> assign(:look, Look.named(connect_param_look(socket) || session["look"]))
      |> attach_hook(:current_path, :handle_params, fn _params, uri, socket ->
        {:cont, assign(socket, :current_path, URI.parse(uri).path)}
      end)
      |> attach_hook(:look, :handle_event, &handle_look_event/3)

    {:cont, socket}
  end

  defp connect_param_look(socket) do
    if connected?(socket), do: (get_connect_params(socket) || %{})["look"]
  end

  defp handle_look_event("set_look", %{"look" => look}, socket),
    do: {:halt, assign(socket, :look, Look.named(look))}

  defp handle_look_event(_event, _params, socket), do: {:cont, socket}
end
