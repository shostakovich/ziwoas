defmodule ZiwoasWeb.SolakonHistoryLive do
  @moduledoc """
  The Solakon-Verlauf on its own (`ZiwoasWeb.SolakonHistoryComponent`): one of
  the ranges 24h, 7d or 30d, anything else reads as 24h. A stored snapshot
  (`Ziwoas.Solakon.subscribe/0`) refreshes it; a range tab patches `?range=`.
  """
  use ZiwoasWeb, :live_view

  alias Ziwoas.Solakon
  alias ZiwoasWeb.SolakonHistoryComponent

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Solakon.subscribe()

    {:ok, assign(socket, page_title: "Solakon-Verlauf", range: nil, refresh: 0)}
  end

  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, assign(socket, :range, params["range"])}

  @impl true
  def handle_info({:snapshot, _}, socket), do: {:noreply, update(socket, :refresh, &(&1 + 1))}
  def handle_info({:reading, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path}>
      <.header class="visually-hidden">Solakon-Verlauf</.header>
      <.live_component
        module={SolakonHistoryComponent}
        id="solakon_history"
        range={@range}
        page={:history}
        refresh={@refresh}
      />
    </Layouts.app>
    """
  end
end
