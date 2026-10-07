defmodule ZiwoasWeb.SolakonHistoryComponent do
  @moduledoc """
  The Solakon-Verlauf, shared by the PV page and `/solakon/history`: range
  tabs, the chart, the energy balance and the outlet's mean power.

  The parent passes `range` (from `?range=`), `page` (`:solakon` or
  `:history`, where the tabs patch to) and `refresh`, which it moves on every
  stored snapshot. Each update loads the history afresh and, once connected,
  pushes the chart's data to the `SolakonHistory` hook as
  `"solakon_history:data"` (`ZiwoasWeb.SolakonComponents.history_chart/1`).
  """
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
