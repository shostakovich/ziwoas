defmodule ZiwoasWeb.DashboardLive do
  @moduledoc """
  The dashboard. Two cadences keep it current:

    * `{:dashboard_live, deltas}` on the `dashboard` topic
      (`Ziwoas.Plugs.ShellyStatusHandler`) and `{:solakon_reading, id}` on
      `solakon` (`Ziwoas.Solakon.MonitorJob`) re-render the hero, the live
      tiles, the plug bar and the energy-flow state, and push the plug deltas
      to the 24 h chart when there are any;
    * a timer recomputes the day's tiles once a minute (`:refresh_summary`).

  Every live update moves `beat`, the `LiveFreshness` hook's heartbeat, and the
  energy flow's `data-state`; plug deltas go to the `TodayChart` hook as a
  `"plug_deltas"` event, which appends them to the 24 h chart in place.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.Components.EnergyFlow
  import ZiwoasWeb.DashboardComponents

  alias Ziwoas.{Clock, Config, EnergySummary, LiveState, Weather}
  alias Ziwoas.Plugs.Measurement
  alias ZiwoasWeb.DashboardComponents

  @summary_interval_ms 60_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ziwoas.PubSub, "dashboard")
      Phoenix.PubSub.subscribe(Ziwoas.PubSub, "solakon")
      :timer.send_interval(@summary_interval_ms, :refresh_summary)
    end

    config = Config.get()

    {:ok,
     socket
     |> assign(page_title: "Dashboard", beat: 0)
     |> assign(
       :summary_tiles,
       DashboardComponents.summary_tiles(EnergySummary.compute_today(config))
     )
     |> load_live()}
  end

  @impl true
  def handle_info({:dashboard_live, deltas}, socket) do
    socket = load_live(socket)

    socket =
      if deltas == [],
        do: socket,
        else: push_event(socket, "plug_deltas", %{deltas: deltas})

    {:noreply, socket}
  end

  def handle_info({:solakon_reading, _id}, socket), do: {:noreply, load_live(socket)}

  def handle_info(:refresh_summary, socket) do
    tiles = DashboardComponents.summary_tiles(EnergySummary.compute_today(Config.get()))
    {:noreply, assign(socket, :summary_tiles, tiles)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path}>
      <.header>Dashboard</.header>

      <div
        id="live_freshness"
        phx-hook="LiveFreshness"
        data-threshold-s={Measurement.offline_after_s()}
        data-beat={@beat}
      >
        <.hero live={@live} weather_asset={@weather_asset} weather_alt={@weather_alt} />

        <div class="row row-cols-2 row-cols-md-4 g-2 mb-3 live-dim">
          <.tile {tile(@summary_tiles, "tile_produced")} />
          <.tile {tile(@summary_tiles, "tile_consumed")} />
          <.tile {tile(@summary_tiles, "tile_savings")} />
          <.tile {tile(@summary_tiles, "tile_net_today")} />
          <.tile :for={live_tile <- @live_tiles} {live_tile} />
          <.tile {tile(@summary_tiles, "tile_autarky")} />
          <.tile {tile(@summary_tiles, "tile_self_consumption")} />
        </div>

        <.energy_flow
          live={@live}
          pv_asset={@weather_asset}
          pv_alt={@weather_alt}
          class="live-dim"
        />

        <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">Steckdosen</h2>
        <.plug_bar live={@live} />

        <div id="today_chart" phx-hook="TodayChart">
          <.card title="Gesamtenergie" subtitle="kWh je Stunde · letzte 24 h">
            <div class="chart-frame" id="today_energy_chart" phx-update="ignore">
              <canvas data-chart="energy"></canvas>
            </div>
          </.card>

          <.card title="Leistung" subtitle="Watt · letzte 24 h">
            <div class="chart-frame" id="today_power_chart" phx-update="ignore">
              <canvas data-chart="power"></canvas>
            </div>
          </.card>
        </div>

        <div id="history_chart" phx-hook="HistoryChart">
          <.card title="Ertrag" subtitle="kWh je Tag · letzte 14 Tage">
            <div class="chart-frame" id="history_chart_frame" phx-update="ignore">
              <canvas></canvas>
            </div>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp tile(tiles, id), do: Enum.find(tiles, &(&1.id == id))

  defp load_live(socket) do
    live = LiveState.build(Config.get(), Clock.now())
    {weather_asset, weather_alt} = ZiwoasWeb.WeatherIcon.dashboard(Weather.latest_current())
    beat = if Map.has_key?(socket.assigns, :live), do: socket.assigns.beat + 1, else: 0

    assign(socket,
      live: live,
      live_tiles: DashboardComponents.live_tiles(live),
      weather_asset: weather_asset,
      weather_alt: weather_alt,
      beat: beat
    )
  end
end
