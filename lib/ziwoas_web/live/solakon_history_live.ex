defmodule ZiwoasWeb.SolakonHistoryLive do
  @moduledoc """
  The Solakon-Verlauf on its own (Rails' `SolakonController#history`, the
  Turbo frame's source): one of the ranges 24h, 7d or 30d, anything else
  reads as 24h. It reloads every minute, as the frame does; a range tab swaps
  it in place.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.SolakonComponents

  alias Ziwoas.{Clock, Config}
  alias Ziwoas.Solakon.History
  alias ZiwoasWeb.DashboardLive

  @refresh_ms 60_000

  @doc "The frame's refresh beat (`REFRESH_MS` of the solakon-history controller)."
  def schedule_refresh, do: Process.send_after(self(), :refresh_history, @refresh_ms)

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    {:ok,
     assign(socket,
       history: History.payload(params["range"], Clock.now(), zone()),
       history_beat: 0
     )}
  end

  @impl true
  def handle_event("history_range", %{"range" => range}, socket),
    do: {:noreply, reload_history(socket, range)}

  @impl true
  def handle_info(:refresh_history, socket) do
    schedule_refresh()
    {:noreply, reload_history(socket, socket.assigns.history.range)}
  end

  @doc """
  Renders the history for `range` under a new frame id, so the chart
  controller reconnects (a refresh, or a range tab as the frame's navigation).
  """
  def reload_history(socket, range) do
    assign(socket,
      history: History.payload(range, Clock.now(), zone()),
      history_beat: socket.assigns.history_beat + 1
    )
  end

  defp zone, do: Config.app_config().location.timezone

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app look={@look} current_path={@current_path}>
      <.history
        history={@history}
        frame_id={DashboardLive.carrier_id("solakon_history", @history_beat)}
      />
    </Layouts.app>
    """
  end
end
