defmodule ZiwoasWeb.SensorsLive do
  @moduledoc """
  The Sensoren page (Rails' `SensorsController#index`). Rails replaces its
  `sensors_dashboard` frame over the `sensors` Turbo stream after every
  sensor poll; here `{:sensors_updated}` on the `sensors` PubSub topic
  (`Ziwoas.Live.SensorsWatcher`) reloads the same part.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.SensorsComponents

  alias Ziwoas.{Clock, Config, Sensors}

  @topic "sensors"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)
    {:ok, socket |> assign(:page_title, "Sensoren") |> load()}
  end

  @impl true
  def handle_info({:sensors_updated}, socket), do: {:noreply, load(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app look={@look} current_path={@current_path} main_class="app-main-wide">
      <h1 class="h2 mb-3">Sensoren</h1>
      <.dashboard sensors={@sensors} latest={@latest} now={@now} />
    </Layouts.app>
    """
  end

  defp load(socket) do
    sensors = Config.app_config().sensors

    assign(socket,
      sensors: sensors,
      latest: sensors |> Enum.map(& &1.id) |> Sensors.latest_per_device(),
      now: Clock.now()
    )
  end
end
