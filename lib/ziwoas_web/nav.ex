defmodule ZiwoasWeb.Nav do
  @moduledoc """
  `on_mount` for every LiveView: the look from the session and the request
  path the navigation marks as current.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias Ziwoas.Look

  def on_mount(:default, _params, session, socket) do
    Ziwoas.Repo.inherit_dynamic_repo()

    socket =
      socket
      |> assign(:look, Look.named(session["look"]))
      |> attach_hook(:current_path, :handle_params, fn _params, uri, socket ->
        {:cont, assign(socket, :current_path, URI.parse(uri).path)}
      end)

    {:cont, socket}
  end
end
