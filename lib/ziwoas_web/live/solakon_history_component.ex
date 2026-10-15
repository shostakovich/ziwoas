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

    # A month of two-minute snapshots is too heavy for the first, static render.
    chart = if connected?(socket), do: JSON.encode!(history_chart(history))

    {:ok, assign(socket, history: history, chart: chart)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.history id={@id} history={@history} chart={@chart} page={@page} />
    </div>
    """
  end
end
