defmodule ZiwoasWeb.SensorsLive do
  @moduledoc false
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.RoomAirComponents, only: [room: 1, room_strip: 1, anchors: 1]
  import ZiwoasWeb.SensorsComponents

  alias Ziwoas.{Clock, Config, Sensors}
  alias Ziwoas.Sensors.Reading
  alias ZiwoasWeb.Charts.RoomAir

  @chart_window_s 24 * 3600
  # Ages and stale lead sensors show without waiting for the next reading.
  @refresh_ms 60_000
  # A full payload now and then re-reads what an append could miss, whatever the sensors.
  @replace_ms 15 * 60_000

  @impl true
  def mount(_params, _session, socket) do
    socket = socket |> assign(:page_title, "Sensoren") |> load()

    if connected?(socket) do
      Sensors.subscribe()
      Process.send_after(self(), :refresh, @refresh_ms)
      Process.send_after(self(), :replace_charts, @replace_ms)
      {:ok, socket |> push_room_charts(:replace) |> push_chart()}
    else
      {:ok, socket}
    end
  end

  @impl true
  # Each polled reading already came as a `{:reading, _}`.
  def handle_info({:polled, _instant}, socket), do: {:noreply, socket}

  def handle_info({:reading, %Reading{device_id: id}}, socket) do
    socket = socket |> load() |> push_room_charts(:append)

    {:noreply,
     if(Enum.any?(socket.assigns.other_sensors, &(&1.id == id)),
       do: push_chart(socket),
       else: socket
     )}
  end

  def handle_info(:replace_charts, socket) do
    Process.send_after(self(), :replace_charts, @replace_ms)
    {:noreply, socket |> load() |> push_room_charts(:replace) |> push_chart()}
  end

  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, socket |> load() |> push_room_charts(:append)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path} main_class="app-main-wide">
      <.header>Sensoren</.header>
      <%= if @latest == %{} do %>
        <.card title="Noch keine Sensordaten">
          <p>Die Sensoransicht erscheint, sobald die ersten Messwerte da sind.</p>
        </.card>
      <% else %>
        <.battery_warning sensors={@sensors} latest={@latest} />
        <.room_strip :if={@rooms != []} rooms={@rooms} />
        <.room
          :for={{room, index} <- Enum.with_index(@rooms)}
          room={room}
          first={index == 0}
          latest={@latest}
          outdoor={@outdoor}
          balcony={@balcony}
          now={@now}
          zone={@zone}
        />
        <%= if @other_sensors != [] do %>
          <h2 :if={@rooms != []} class="h4 mb-3">Weitere Sensoren</h2>
          <.sensor_cards sensors={@other_sensors} latest={@latest} now={@now} />
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end

  defp load(socket) do
    config = Config.get()
    now = Clock.now()
    outdoor = Sensors.fresh_outdoor(config, now)

    names = Sensors.rooms(config)
    anchors = anchors(names)

    rooms =
      for name <- names do
        reading = Sensors.room_reading(config, name, now)

        %{
          id: Map.fetch!(anchors, name),
          name: name,
          reading: reading,
          quantities: Sensors.room_quantities(config, name),
          verdict: Sensors.air_verdict(reading),
          hint: Sensors.ventilation_hint(reading, outdoor)
        }
      end

    assign(socket,
      config: config,
      sensors: config.sensors,
      other_sensors: Enum.filter(config.sensors, &is_nil(&1.room)),
      rooms: rooms,
      latest: config.sensors |> Enum.map(& &1.id) |> Sensors.latest_per_device(),
      outdoor: outdoor,
      balcony: Enum.any?(config.sensors, &(&1.type == :outdoor_meter)),
      zone: config.location.timezone,
      now: now
    )
  end

  defp push_room_charts(%{assigns: %{rooms: rooms, config: config, now: now}} = socket, mode) do
    data =
      case {mode, socket.assigns[:charted_to]} do
        {:append, %DateTime{} = charted_to} ->
          &RoomAir.append(config, &1, charted_to, now)

        _replace ->
          &RoomAir.replace(config, &1, DateTime.add(now, -@chart_window_s, :second), now)
      end

    rooms
    |> Enum.reduce(socket, &push_event(&2, "room_air_chart:data", data.(&1)))
    |> assign(:charted_to, now)
  end

  defp push_chart(%{assigns: %{other_sensors: []}} = socket), do: socket

  defp push_chart(%{assigns: %{other_sensors: sensors, now: now}} = socket) do
    readings =
      Sensors.since(Enum.map(sensors, & &1.id), DateTime.add(now, -@chart_window_s, :second))

    push_event(socket, "sensors_chart:data", chart_data(sensors, readings))
  end
end
