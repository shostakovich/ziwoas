defmodule ZiwoasWeb.SolakonHistoryLive do
  @moduledoc """
  The Solakon-Verlauf on its own: one of the ranges 24h, 7d or 30d, anything
  else reads as 24h. It reloads every minute; a range tab patches `?range=`.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.SolakonComponents

  alias Ziwoas.{Clock, Config}
  alias Ziwoas.Solakon.History
  @refresh_ms 60_000

  @doc "The history's minute refresh."
  def schedule_refresh, do: Process.send_after(self(), :refresh_history, @refresh_ms)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, reload_history(socket, params["range"])}

  @impl true
  def handle_info(:refresh_history, socket) do
    schedule_refresh()
    {:noreply, reload_history(socket, socket.assigns.history.range)}
  end

  @doc """
  Renders the history for `range` afresh (a refresh, or a range patch); the
  `SolakonHistory` hook redraws its chart in place from the new payload.
  """
  def reload_history(socket, range),
    do: assign(socket, :history, History.payload(range, Clock.now(), zone()))

  defp zone, do: Config.app_config().location.timezone

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path}>
      <.history history={@history} path={~p"/solakon/history"} />
    </Layouts.app>
    """
  end
end
