defmodule ZiwoasWeb.SolakonHistoryComponent do
  @moduledoc false
  use ZiwoasWeb, :live_component

  import ZiwoasWeb.SolakonComponents

  alias Ziwoas.{Clock, Config, Solakon}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    zone = Config.get().location.timezone
    history = Solakon.history(socket.assigns.range, Clock.now(), zone)
    socket = assign(socket, :history, history)

    socket =
      if connected?(socket),
        do: push_event(socket, "solakon_history:data", history_chart(history)),
        else: socket

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook="SolakonHistory" data-range={@history.range}>
      <.history id={@id} history={@history} page={@page} />
    </div>
    """
  end
end
