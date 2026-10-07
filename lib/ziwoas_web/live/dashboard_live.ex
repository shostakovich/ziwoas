defmodule ZiwoasWeb.DashboardLive do
  @moduledoc """
  The dashboard (Rails' `DashboardController#index`). Rails refreshes its live
  regions over the `dashboard_live` Turbo stream (`DashboardBroadcaster`);
  here the `dashboard` and `solakon` PubSub topics carry the same two
  cadences (`Ziwoas.Live.DashboardWatcher`, `Ziwoas.Live.SolakonWatcher`):

    * `{:dashboard_live, deltas}` and `{:solakon_reading, id}` re-render the
      hero, the live tiles, the plug bar and the energy-flow state, plus the
      plug deltas for the 24 h chart when there are any (`broadcast_live`);
    * `{:dashboard_summary}` recomputes the day's tiles (`broadcast_summary`).

  The data carriers for Stimulus (`energy_flow_state`, `plug_deltas`) take a
  new id on every update, so the client replaces them and the controllers'
  `*TargetConnected` callbacks fire, as with a Turbo `replace`.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.CoreComponents
  import ZiwoasWeb.DashboardComponents

  alias Ziwoas.{Clock, Config, EnergySummary, LiveState, Weather}
  alias Ziwoas.Plugs.Measurement
  alias ZiwoasWeb.DashboardComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ziwoas.PubSub, "dashboard")
      Phoenix.PubSub.subscribe(Ziwoas.PubSub, "solakon")
    end

    config = Config.app_config()

    {:ok,
     socket
     |> assign(page_title: "Dashboard", beat: 0, deltas: "[]", deltas_beat: 0)
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
        else:
          assign(socket,
            deltas: Ziwoas.RubyJSON.encode!(deltas),
            deltas_beat: socket.assigns.deltas_beat + 1
          )

    {:noreply, socket}
  end

  def handle_info({:solakon_reading, _id}, socket), do: {:noreply, load_live(socket)}

  def handle_info({:dashboard_summary}, socket) do
    tiles = DashboardComponents.summary_tiles(EnergySummary.compute_today(Config.app_config()))
    {:noreply, assign(socket, :summary_tiles, tiles)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app look={@look} current_path={@current_path}>
      <h1 class="h2 mb-3">Dashboard</h1>

      <div
        data-controller="live-freshness"
        data-live-freshness-threshold-s-value={Measurement.offline_after_s()}
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

        <.card title="Energiefluss" class="energy-flow-card live-dim" data-controller="energy-flow">
          <.energy_flow_state live={@live} id={carrier_id("energy_flow_state", @beat)} />
          <.energy_flow
            pv_asset={@weather_asset}
            pv_alt={@weather_alt}
            battery_asset={DashboardComponents.default_battery_asset()}
          />
        </.card>

        <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">Steckdosen</h2>
        <.plug_bar live={@live} />

        <div data-controller="today-chart">
          <.plug_deltas deltas={@deltas} id={carrier_id("plug_deltas", @deltas_beat)} />

          <.card title="Gesamtenergie" subtitle="kWh je Stunde · letzte 24 h">
            <div class="chart-frame">
              <canvas data-today-chart-target="energyCanvas"></canvas>
            </div>
          </.card>

          <.card title="Leistung" subtitle="Watt · letzte 24 h">
            <div class="chart-frame">
              <canvas data-today-chart-target="powerCanvas"></canvas>
            </div>
          </.card>
        </div>

        <div data-controller="history-chart">
          <.card title="Ertrag" subtitle="kWh je Tag · letzte 14 Tage">
            <div class="chart-frame">
              <canvas data-history-chart-target="canvas"></canvas>
            </div>
          </.card>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @doc "Rails' id on the first render, another one on every update, so the client replaces the element."
  def carrier_id(base, 0), do: base
  def carrier_id(base, beat), do: "#{base}-#{beat}"

  defp tile(tiles, id), do: Enum.find(tiles, &(&1.id == id))

  defp load_live(socket) do
    live = LiveState.build(Config.app_config(), Clock.now())
    {weather_asset, weather_alt} = Weather.dashboard_icon()
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
