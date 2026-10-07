defmodule ZiwoasWeb.SensorsLive do
  @moduledoc """
  The Sensoren page. On a connected mount and after every poll
  (`Ziwoas.Sensors.subscribe/0`) it reloads the cards and pushes the last 24 hours
  to the `SensorsChart` hook (`"sensors_chart:data"`, see
  `ZiwoasWeb.SensorsComponents.chart_data/2`).
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.SensorsComponents

  alias Ziwoas.{Clock, Config, Sensors}

  @chart_window_s 24 * 3600

  @impl true
  def mount(_params, _session, socket) do
    socket = socket |> assign(:page_title, "Sensoren") |> load()

    if connected?(socket) do
      Sensors.subscribe()
      {:ok, push_chart(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_info({:polled, _instant}, socket),
    do: {:noreply, socket |> load() |> push_chart()}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path} main_class="app-main-wide">
      <.header>Sensoren</.header>
      <.dashboard sensors={@sensors} latest={@latest} now={@now} />
    </Layouts.app>
    """
  end

  defp load(socket) do
    sensors = Config.get().sensors

    assign(socket,
      sensors: sensors,
      latest: sensors |> device_ids() |> Sensors.latest_per_device(),
      now: Clock.now()
    )
  end

  defp push_chart(%{assigns: %{sensors: sensors, now: now}} = socket) do
    readings = Sensors.since(device_ids(sensors), DateTime.add(now, -@chart_window_s, :second))
    push_event(socket, "sensors_chart:data", chart_data(sensors, readings))
  end

  defp device_ids(sensors), do: Enum.map(sensors, & &1.id)
end
