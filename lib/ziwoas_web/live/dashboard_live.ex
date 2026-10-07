defmodule ZiwoasWeb.DashboardLive do
  @moduledoc false
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.Components.EnergyFlow
  import ZiwoasWeb.DashboardComponents

  alias Ziwoas.{Clock, Config, Energy, LocalDay, Plugs, Solakon, Weather}
  alias Ziwoas.Plugs.Measurement
  alias ZiwoasWeb.Charts
  alias ZiwoasWeb.DashboardComponents

  @summary_throttle_s 60
  @today_chart_refresh_ms 3_600_000

  @impl true
  def mount(_params, _session, socket) do
    config = Config.get()

    socket =
      socket
      |> assign(page_title: "Dashboard", beat: 0)
      |> assign_summary(config)
      |> load_live()

    if connected?(socket) do
      Plugs.subscribe()
      Plugs.subscribe(:aggregated)
      Solakon.subscribe()
      schedule_midnight(config)
      Process.send_after(self(), :slide_today_chart, @today_chart_refresh_ms)
    end

    {:ok,
     if(connected?(socket),
       do: socket |> push_today_chart(config) |> push_history_chart(config),
       else: socket
     )}
  end

  @impl true
  def handle_info({:live, deltas}, socket) do
    socket = socket |> load_live() |> maybe_refresh_summary()

    socket =
      if deltas == [],
        do: socket,
        else: push_event(socket, "today_chart:deltas", %{deltas: deltas})

    {:noreply, socket}
  end

  def handle_info({:reading, _reading}, socket), do: {:noreply, load_live(socket)}

  def handle_info({:aggregated, _date}, socket),
    do: {:noreply, push_history_chart(socket, Config.get())}

  def handle_info(:midnight, socket) do
    config = Config.get()
    schedule_midnight(config)
    {:noreply, socket |> assign_summary(config) |> push_history_chart(config)}
  end

  def handle_info(:slide_today_chart, socket) do
    Process.send_after(self(), :slide_today_chart, @today_chart_refresh_ms)
    {:noreply, push_today_chart(socket, Config.get())}
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

  defp assign_summary(socket, config) do
    assign(socket,
      summary_tiles: DashboardComponents.summary_tiles(Energy.today(config)),
      summary_at: Clock.unix_now()
    )
  end

  defp maybe_refresh_summary(socket) do
    if Clock.unix_now() - socket.assigns.summary_at >= @summary_throttle_s,
      do: assign_summary(socket, Config.get()),
      else: socket
  end

  defp schedule_midnight(config) do
    zone = config.location.timezone
    next_midnight = zone |> Clock.today() |> Date.add(1) |> LocalDay.midnight(zone)
    delay_ms = max(DateTime.diff(next_midnight, Clock.now(), :millisecond), 0)
    Process.send_after(self(), :midnight, delay_ms)
  end

  defp push_today_chart(socket, config),
    do: push_event(socket, "today_chart:data", Charts.Dashboard.today(config))

  defp push_history_chart(socket, config) do
    today = Clock.today(config.location.timezone)
    push_event(socket, "history_chart:data", Charts.Dashboard.history(config, today))
  end

  defp load_live(socket) do
    live = Energy.live_state(Config.get(), Clock.now())
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
