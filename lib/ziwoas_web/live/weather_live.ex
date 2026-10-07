defmodule ZiwoasWeb.WeatherLive do
  @moduledoc """
  The Wetter page. A weather sync (`Ziwoas.Weather.subscribe/0`) or a sensor
  poll (`Ziwoas.Sensors.subscribe/0`, the outdoor sensor's temperature) reloads it.

  A segment tile of the next days opens that segment's hours below the tiles and
  closes the day's other segment (`"toggle_segment"`); the choice outlives a reload.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.WeatherComponents

  alias Ziwoas.{Clock, Config, Sensors, Weather}

  # A day's four segments by the tile's `phx-value-index`.
  @segment_indexes %{"0" => 0, "1" => 1, "2" => 2, "3" => 3}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Weather.subscribe()
      Sensors.subscribe()
    end

    {:ok, socket |> assign(page_title: "Wetter", open_segments: %{}) |> load()}
  end

  @impl true
  def handle_event("toggle_segment", %{"day" => day, "index" => index}, socket)
      when is_map_key(@segment_indexes, index) and is_binary(day) do
    index = @segment_indexes[index]

    open =
      if socket.assigns.open_segments[day] == index,
        do: Map.delete(socket.assigns.open_segments, day),
        else: Map.put(socket.assigns.open_segments, day, index)

    {:noreply, assign(socket, :open_segments, open)}
  end

  def handle_event("toggle_segment", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:synced, _today}, socket), do: {:noreply, load(socket)}
  def handle_info({:polled, _instant}, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path}>
      <.header>Wetter</.header>

      <.empty current={@current} today={@today} days={@days} />
      <.current current={@current} sensor={@sensor} />
      <.today records={@today} zone={@zone} />
      <.forecast days={@days} zone={@zone} open={@open_segments} />
    </Layouts.app>
    """
  end

  defp load(socket) do
    config = Config.get()
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
