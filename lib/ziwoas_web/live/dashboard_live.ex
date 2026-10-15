defmodule ZiwoasWeb.DashboardLive do
  @moduledoc false
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.Components.EnergyFlow
  import ZiwoasWeb.DashboardComponents
  import ZiwoasWeb.LiveFreshness, only: [live_header: 1]
  import ZiwoasWeb.RoomAirComponents, only: [dashboard_tile: 1]

  alias Ziwoas.{Clock, Config, Energy, LocalDay, Plugs, Sensors, Solakon, Sun, Weather}
  alias Ziwoas.Plugs.Roster
  alias ZiwoasWeb.{Charts, DashboardComponents, RoomAirComponents, WeatherIcon}

  on_mount ZiwoasWeb.LiveFreshness

  @summary_throttle_s 60
  @today_chart_refresh_ms 3_600_000
  # A silent sensor must not keep a stale verdict on the tile.
  @room_air_refresh_ms 60_000

  @impl true
  def mount(_params, _session, socket) do
    config = Config.get()
    roster = Config.plug_roster(config)

    socket =
      socket
      |> assign(
        page_title: "Home",
        zone: config.location.timezone,
        roster: roster,
        producers: roster |> Roster.producers() |> Enum.map(& &1.name),
        consumers: roster |> Roster.consumers() |> Enum.map(&{&1.id, &1.name}),
        today_chart: nil,
        history: nil
      )
      |> assign_summary(config)
      |> assign_rank(config)
      |> assign_room_air(config)
      |> load_live()

    if connected?(socket) do
      Plugs.subscribe()
      Plugs.subscribe(:aggregated)
      Solakon.subscribe()
      Sensors.subscribe()
      Process.send_after(self(), :refresh_room_air, @room_air_refresh_ms)
      schedule_midnight(config)
      Process.send_after(self(), :slide_today_chart, @today_chart_refresh_ms)
    end

    {:ok,
     if(connected?(socket),
       do: socket |> assign_today_chart(config) |> assign_history(config),
       else: socket
     )}
  end

  @impl true
  def handle_info({:live, deltas}, socket) do
    socket = socket |> load_live() |> maybe_refresh_summary() |> fill_empty_today_chart(deltas)

    socket =
      if deltas == [],
        do: socket,
        else: push_event(socket, "today_chart:deltas", %{deltas: deltas})

    {:noreply, socket}
  end

  def handle_info({:reading, %Sensors.Reading{}}, socket),
    do: {:noreply, assign_room_air(socket, Config.get())}

  def handle_info({:polled, _instant}, socket),
    do: {:noreply, assign_room_air(socket, Config.get())}

  def handle_info(:refresh_room_air, socket) do
    Process.send_after(self(), :refresh_room_air, @room_air_refresh_ms)
    {:noreply, assign_room_air(socket, Config.get())}
  end

  def handle_info({:reading, _reading}, socket), do: {:noreply, load_live(socket)}

  def handle_info({:snapshot, _snapshot}, socket), do: {:noreply, socket}

  def handle_info({:aggregated, _date}, socket) do
    config = Config.get()
    {:noreply, socket |> assign_rank(config) |> assign_history(config)}
  end

  def handle_info(:midnight, socket) do
    config = Config.get()
    schedule_midnight(config)
    {:noreply, socket |> assign_summary(config) |> assign_rank(config) |> assign_history(config)}
  end

  def handle_info(:slide_today_chart, socket) do
    Process.send_after(self(), :slide_today_chart, @today_chart_refresh_ms)
    {:noreply, assign_today_chart(socket, Config.get())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} width={:default}>
      <.live_header stale={@stale} live_at={@live_at} zone={@zone}>Home</.live_header>

      <div class="flex flex-col gap-8">
        <div class="flex flex-col gap-4 md:gap-6">
          <div class="grid grid-cols-2 gap-4 md:gap-6 lg:grid-cols-4">
            <.hero
              live={@live}
              weather_plush={@weather_plush}
              weather_alt={@weather_alt}
              class="col-span-2"
            />
            <.stat :for={tile <- @live_tiles} {tile} size={:sm} stale={@stale} />
          </div>

          <div class="grid gap-4 md:gap-6 lg:grid-cols-2">
            <.energy_flow live={@live} class="min-w-0" />
            <div class="flex min-w-0 flex-col gap-4 md:gap-6">
              <.plug_bar live={@live} rank={@rank} class={@room_air && "flex-1"} />
              <div :if={@room_air}><.dashboard_tile tile={@room_air} /></div>
            </div>
          </div>
        </div>

        <section aria-labelledby="today_heading">
          <.section_heading id="today_heading">Heute</.section_heading>
          <div class="flex flex-col gap-4 md:gap-6">
            <div class="setzkasten-stat-grid grid grid-cols-2 gap-4 md:grid-cols-3 md:gap-6">
              <.stat :for={tile <- @summary_tiles} {tile} size={:sm} />
            </div>
            <.today_charts
              chart={@today_chart}
              producers={@producers}
              consumers={@consumers}
              rank={@rank}
              roster={@roster}
              zone={@zone}
            />
          </div>
        </section>

        <section :if={@producers != []} aria-labelledby="history_heading">
          <.section_heading id="history_heading">Verlauf</.section_heading>
          <.history_chart points={@history} />
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp assign_summary(socket, config) do
    assign(socket,
      summary_tiles: DashboardComponents.summary_tiles(Energy.today(config)),
      summary_at: Clock.unix_now()
    )
  end

  defp assign_rank(socket, config),
    do:
      assign(
        socket,
        :rank,
        Plugs.consumer_rank(config.plugs, Clock.today(config.location.timezone))
      )

  defp assign_room_air(socket, config) do
    now = Clock.now()

    room_air =
      with display when is_binary(display) <- Sensors.display_room(config) do
        anchors = config |> Sensors.rooms() |> RoomAirComponents.anchors()

        [
          display
          | Enum.filter(Sensors.rooms(config), &(:co2 in Sensors.room_quantities(config, &1)))
        ]
        |> Enum.uniq()
        |> Enum.map(&room_tile(config, &1, anchors, now))
        |> Enum.max_by(&severity(&1.verdict))
      end

    assign(socket, :room_air, room_air)
  end

  defp room_tile(config, name, anchors, now) do
    reading = Sensors.room_reading(config, name, now)

    %{
      id: Map.fetch!(anchors, name),
      name: name,
      reading: reading,
      quantities: Sensors.room_quantities(config, name),
      verdict: Sensors.air_verdict(reading),
      now: now
    }
  end

  defp severity({:bad, _quantities}), do: 3
  defp severity({:warn, _quantities}), do: 2
  defp severity({:good, _quantities}), do: 1
  defp severity(nil), do: 0

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

  # An empty chart has no hook to take deltas, so the first readings redraw it whole.
  defp fill_empty_today_chart(%{assigns: %{today_chart: chart}} = socket, [_ | _])
       when not is_nil(chart) do
    if Charts.Dashboard.measured?(chart),
      do: socket,
      else: assign_today_chart(socket, Config.get())
  end

  defp fill_empty_today_chart(socket, _deltas), do: socket

  defp assign_today_chart(socket, config),
    do: assign(socket, :today_chart, Charts.Dashboard.today(config))

  defp assign_history(socket, config) do
    today = Clock.today(config.location.timezone)
    assign(socket, :history, Charts.Dashboard.history(config, today).points)
  end

  defp load_live(socket) do
    config = Config.get()
    now = Clock.now()
    live = Energy.live_state(config, now)
    {weather_plush, weather_alt} = weather(Weather.latest_current(), config.location, now)

    assign(socket,
      live: live,
      live_tiles: DashboardComponents.live_tiles(live),
      weather_plush: weather_plush,
      weather_alt: weather_alt
    )
  end

  defp weather(%{icon: icon} = record, location, now) when is_binary(icon) do
    if String.trim(icon) == "",
      do: weather(nil, location, now),
      else:
        {WeatherIcon.current_plush_name(record, Sun.daytime?(location, now)),
         WeatherIcon.label(icon)}
  end

  defp weather(_record, _location, _now), do: {"sun", "Sonne"}
end
