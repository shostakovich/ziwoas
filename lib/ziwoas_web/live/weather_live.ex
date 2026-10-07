defmodule ZiwoasWeb.WeatherLive do
  @moduledoc """
  The Wetter page (Rails' `WeatherController#index`). Rails refreshes it over
  the `weather` Turbo stream; here a `{:weather_updated}` on the `weather`
  PubSub topic reloads it once something publishes there.

  A segment tile of the next days opens that segment's hours below the tiles and
  closes the day's other segment (`"toggle_segment"`); the choice outlives a reload.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.WeatherComponents

  alias Ziwoas.{Clock, Config, Sensors, Weather}

  @topic "weather"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)
    {:ok, socket |> assign(page_title: "Wetter", open_segments: %{}) |> load()}
  end

  @impl true
  def handle_event("toggle_segment", %{"day" => day, "index" => index}, socket) do
    index = String.to_integer(index)

    open =
      if socket.assigns.open_segments[day] == index,
        do: Map.delete(socket.assigns.open_segments, day),
        else: Map.put(socket.assigns.open_segments, day, index)

    {:noreply, assign(socket, :open_segments, open)}
  end

  @impl true
  def handle_info({:weather_updated}, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app look={@look} current_path={@current_path}>
      <h1 class="h2 mb-3">Wetter</h1>

      <.empty current={@current} today={@today} days={@days} />
      <.current current={@current} sensor={@sensor} />
      <.today records={@today} zone={@zone} />
      <.forecast days={@days} zone={@zone} open={@open_segments} />
    </Layouts.app>
    """
  end

  defp load(socket) do
    config = Config.app_config()
    zone = config.location.timezone
    now = Clock.now()

    assign(socket,
      zone: zone,
      current: Weather.latest_current(),
      today: Weather.today_hourly(now, zone),
      days: Weather.future_days(Clock.today(zone), zone),
      sensor: Sensors.fresh_outdoor(outdoor_sensor_ids(config), now)
    )
  end

  defp outdoor_sensor_ids(config),
    do: for(%{type: :outdoor_meter, id: id} <- config.sensors, do: id)
end
