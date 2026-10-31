defmodule ZiwoasWeb.SolakonLive do
  @moduledoc false
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.Components.EnergyFlow
  import ZiwoasWeb.Components.Shading
  import ZiwoasWeb.Components.SunCalendar
  import ZiwoasWeb.EconomicsComponents
  import ZiwoasWeb.LiveFreshness, only: [live_header: 1]
  import ZiwoasWeb.SolakonComponents

  require Logger

  alias Ziwoas.{Clock, Config, Economics, Energy, Plugs, Shading, Solakon, SunCalendar}
  alias Ziwoas.Plugs.Roster
  alias Ziwoas.Solakon.{Reading, Snapshot}
  alias ZiwoasWeb.SolakonHistoryComponent

  on_mount ZiwoasWeb.LiveFreshness

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Plugs.subscribe()
      Solakon.subscribe()
    end

    config = Config.get()
    now = Clock.now()
    location = config.location
    control_enabled = (config.solakon && config.solakon.control_enabled) == true
    producer_ids = config |> Config.plug_roster() |> Roster.producer_ids()
    reading = Solakon.latest_reading()

    {:ok,
     socket
     |> assign(
       page_title: "PV",
       zone: location.timezone,
       live: Energy.live_state(config, now),
       reading: reading,
       snapshot: Solakon.latest_snapshot(),
       inverter: match?(%{monitoring_enabled: true}, config.solakon),
       eps_on: eps_on?(reading),
       eps_target: nil,
       eps_error: nil,
       control_enabled: control_enabled,
       control_active: control_enabled and Solakon.control_active?(),
       control_target: nil,
       control_error: nil,
       history_range: nil,
       history_refresh: 0
     )
     |> assign_async(:sun_calendar, fn ->
       year = SunCalendar.latest_year(location, now)
       {:ok, %{sun_calendar: SunCalendar.year(location, producer_ids, year)}}
     end)
     |> assign_async(:shading, fn -> {:ok, %{shading: Shading.report(location, now)}} end)
     |> assign_async(:economics, fn ->
       {:ok, %{economics: Economics.overview(Clock.today(location.timezone))}}
     end)}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, assign(socket, :history_range, params["range"])}

  @impl true
  def handle_info({:live, _deltas}, socket), do: {:noreply, assign_live(socket)}

  def handle_info({:reading, %Reading{} = reading}, socket),
    do: {:noreply, socket |> assign_live() |> assign_reading(reading)}

  def handle_info({:snapshot, %Snapshot{} = snapshot}, socket) do
    {:noreply, socket |> assign(:snapshot, snapshot) |> update(:history_refresh, &(&1 + 1))}
  end

  defp assign_live(socket),
    do: assign(socket, :live, Energy.live_state(Config.get(), Clock.now()))

  defp assign_reading(%{assigns: %{eps_target: nil}} = socket, reading),
    do: assign(socket, reading: reading, eps_on: eps_on?(reading))

  defp assign_reading(socket, reading), do: assign(socket, :reading, reading)

  defp eps_on?(reading), do: reading != nil and reading.eps_enabled == true

  @impl true
  def handle_event("toggle_eps", _params, %{assigns: %{eps_target: target}} = socket)
      when is_boolean(target),
      do: {:noreply, socket}

  def handle_event("toggle_eps", %{"eps" => value}, socket) do
    desired = value == "true"

    {:noreply,
     socket
     |> assign(eps_target: desired)
     |> start_async(:eps, fn -> Solakon.set_eps_output(desired) end)}
  end

  def handle_event("toggle_eps", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_control", _params, %{assigns: %{control_target: target}} = socket)
      when is_boolean(target),
      do: {:noreply, socket}

  def handle_event("toggle_control", %{"control" => value}, socket) do
    config = Config.get()
    desired = value == "true"

    {:noreply,
     socket
     |> assign(control_target: desired)
     |> start_async(:control, fn -> Solakon.set_control_active(config, desired) end)}
  end

  def handle_event("toggle_control", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:eps, {:ok, {:ok, enabled}}, socket),
    do: {:noreply, assign(socket, eps_on: enabled == true, eps_error: nil, eps_target: nil)}

  def handle_async(:eps, {_, reason}, socket) do
    Logger.warning("solakon_controls: EPS switch failed: #{inspect(reason)}")
    {:noreply, assign(socket, eps_error: "Schalten fehlgeschlagen", eps_target: nil)}
  end

  def handle_async(:control, {:ok, {:ok, active}}, socket) do
    {:noreply, assign(socket, control_active: active, control_error: nil, control_target: nil)}
  end

  def handle_async(:control, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, control_error: control_error(reason), control_target: nil)}

  def handle_async(:control, {:exit, reason}, socket) do
    Logger.warning("solakon_controls: control switch failed: #{inspect(reason)}")
    {:noreply, assign(socket, control_error: "Schalten fehlgeschlagen", control_target: nil)}
  end

  defp control_error(:not_configured), do: "Solakon nicht konfiguriert"
  defp control_error(:disabled), do: "in Konfiguration deaktiviert"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path} width={:default}>
      <.live_header stale={@stale} live_at={@live_at} zone={@zone}>PV</.live_header>

      <div class="flex flex-col gap-8">
        <.energy_flow live={@live} />

        <.status reading={@reading} snapshot={@snapshot} />
        <.controls
          reading={@reading}
          inverter={@inverter}
          eps_on={@eps_on}
          eps_target={@eps_target}
          eps_error={@eps_error}
          control_enabled={@control_enabled}
          control_active={@control_active}
          control_target={@control_target}
          control_error={@control_error}
        />
        <.panels snapshot={@snapshot} stale={@stale} />
        <.storage reading={@reading} snapshot={@snapshot} stale={@stale} />

        <section aria-labelledby="solakon-history-heading">
          <.section_heading id="solakon-history-heading">PV-Verlauf</.section_heading>
          <.live_component
            module={SolakonHistoryComponent}
            id="solakon_history"
            range={@history_range}
            page={:solakon}
            refresh={@history_refresh}
          />
        </section>

        <.async_result :let={economics} assign={@economics}>
          <:loading>
            <section data-async="loading" aria-labelledby="economics-heading">
              <.overview_heading />
              <div class="setzkasten-stat-grid grid grid-cols-2 md:grid-cols-3 gap-3 md:gap-4">
                <.stat label="Anschaffungs­kosten" size={:sm} loading />
                <.stat label="Ersparnis" size={:sm} loading />
                <.stat
                  label="Voraus­sichtliche Amortisation"
                  size={:sm}
                  loading
                  class="col-span-2 md:col-span-1"
                />
              </div>
            </section>
          </:loading>
          <:failed>
            <section data-async="failed" aria-labelledby="economics-heading">
              <.overview_heading />
              <.alert tone={:error}>Konnte nicht berechnet werden.</.alert>
            </section>
          </:failed>
          <.overview result={economics} />
        </.async_result>

        <.async_result :let={calendar} assign={@sun_calendar}>
          <:loading>
            <.pending id="sun-pending" title="Sonnenkalender" chart="PV-Leistung" />
          </:loading>
          <:failed><.failed title="Sonnenkalender" /></:failed>
          <.sun_calendar calendar={calendar} />
        </.async_result>

        <.async_result :let={report} assign={@shading}>
          <:loading>
            <.pending id="shading-pending" title="Ausbeute" chart="Ausbeute nach Sonnenstand" />
          </:loading>
          <:failed><.failed title="Ausbeute" /></:failed>
          <.shading report={report} />
        </.async_result>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :chart, :string, required: true

  defp pending(assigns) do
    ~H"""
    <section data-async="loading">
      <.section_heading>{@title}</.section_heading>
      <.chart_card id={@id} title={@chart} summary={"#{@chart} wird berechnet"} level={3} loading />
    </section>
    """
  end

  attr :title, :string, required: true

  defp failed(assigns) do
    ~H"""
    <section data-async="failed">
      <.section_heading>{@title}</.section_heading>
      <.alert tone={:error}>Konnte nicht berechnet werden.</.alert>
    </section>
    """
  end
end
