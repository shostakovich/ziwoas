defmodule ZiwoasWeb.Nav do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:default, _params, session, socket) do
    {:cont,
     socket
     |> assign(:resident, session["resident"])
     |> attach_hook(:current_path, :handle_params, fn _params, uri, socket ->
       {:cont, assign(socket, :current_path, URI.parse(uri).path)}
     end)}
  end
end
