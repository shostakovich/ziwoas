defmodule ZiwoasWeb.SolakonLive do
  @moduledoc """
  The PV page. Plug deltas (`Ziwoas.Plugs.subscribe/0`) and stored readings
  (`Ziwoas.Solakon.subscribe/0`) replace the energy-flow state and move the
  freshness beat; a stored snapshot refreshes the Solakon-Verlauf
  (`ZiwoasWeb.SolakonHistoryComponent`), whose range tabs patch `?range=`.
  The sun calendar, the shading report and the Wirtschaftlichkeit load after
  the page is connected.

  The EPS and Auto-Regelung switches are the events `"toggle_eps"` and
  `"toggle_control"`; their writes run off the LiveView process.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.Components.EnergyFlow
  import ZiwoasWeb.Components.Shading
  import ZiwoasWeb.Components.SunCalendar
  import ZiwoasWeb.EconomicsComponents
  import ZiwoasWeb.SolakonComponents

  require Logger

  alias Ziwoas.{Clock, Config, LiveState, Plugs, Shading, Solakon, SunCalendar}
  alias Ziwoas.Economics.Overview
  alias Ziwoas.Plugs.{Measurement, Roster}
  alias ZiwoasWeb.SolakonHistoryComponent

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
       beat: 0,
       live: LiveState.build(config, now),
       reading: reading,
       snapshot: Solakon.latest_snapshot(),
       eps_on: reading != nil and reading.eps_enabled == true,
       eps_pending: false,
       eps_error: nil,
       control_enabled: control_enabled,
       control_active: control_enabled and Solakon.control_active?(),
       control_pending: false,
       control_help: nil,
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
       {:ok, %{economics: Overview.build(Clock.today(location.timezone))}}
     end)}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, assign(socket, :history_range, params["range"])}

  @impl true
  def handle_info({event, _}, socket) when event in [:live, :reading] do
    {:noreply,
     assign(socket,
       live: LiveState.build(Config.get(), Clock.now()),
       beat: socket.assigns.beat + 1
     )}
  end

  def handle_info({:snapshot, _}, socket),
    do: {:noreply, update(socket, :history_refresh, &(&1 + 1))}

  @impl true
  def handle_event("toggle_eps", _params, %{assigns: %{eps_pending: true}} = socket),
    do: {:noreply, socket}

  def handle_event("toggle_eps", _params, socket) do
    desired = not socket.assigns.eps_on

    socket =
      if is_nil(Config.get().solakon),
        do: assign(socket, eps_error: "Solakon nicht konfiguriert"),
        else:
          socket
          |> assign(eps_pending: true)
          |> start_async(:eps, fn -> Solakon.set_eps_output(desired) end)

    {:noreply, socket}
  end

  def handle_event("toggle_control", _params, %{assigns: %{control_pending: true}} = socket),
    do: {:noreply, socket}

  def handle_event("toggle_control", _params, socket) do
    config = Config.get()
    desired = not socket.assigns.control_active

    {:noreply,
     socket
     |> assign(control_pending: true)
     |> start_async(:control, fn -> Solakon.set_control_active(config, desired) end)}
  end

  @impl true
  def handle_async(:eps, {:ok, {:ok, enabled}}, socket),
    do: {:noreply, assign(socket, eps_on: enabled == true, eps_error: nil, eps_pending: false)}

  def handle_async(:eps, {_, reason}, socket) do
    Logger.warning("solakon_controls: EPS switch failed: #{inspect(reason)}")
    {:noreply, assign(socket, eps_error: "Schalten fehlgeschlagen", eps_pending: false)}
  end

  def handle_async(:control, {:ok, {:ok, active}}, socket) do
    {:noreply,
     assign(socket,
       control_active: active,
       control_help: if(active, do: "folgt dem gemessenen Verbrauch", else: "pausiert"),
       control_error: nil,
       control_pending: false
     )}
  end

  def handle_async(:control, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, control_error: control_error(reason), control_pending: false)}

  def handle_async(:control, {:exit, reason}, socket) do
    Logger.warning("solakon_controls: control switch failed: #{inspect(reason)}")
    {:noreply, assign(socket, control_error: "Schalten fehlgeschlagen", control_pending: false)}
  end

  defp control_error(:not_configured), do: "Solakon nicht konfiguriert"
  defp control_error(:disabled), do: "in Konfiguration deaktiviert"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path} main_class="app-main-wide">
      <.header>PV</.header>

      <div
        id="live_freshness"
        phx-hook="LiveFreshness"
        data-threshold-s={Measurement.offline_after_s()}
        data-beat={@beat}
      >
        <.energy_flow live={@live} pv_asset="icon_sonne.webp" pv_alt="PV" />

        <.status reading={@reading} snapshot={@snapshot} />
        <.controls
          reading={@reading}
          eps_on={@eps_on}
          eps_pending={@eps_pending}
          eps_error={@eps_error}
          control_enabled={@control_enabled}
          control_active={@control_active}
          control_pending={@control_pending}
          control_help={@control_help}
          control_error={@control_error}
        />
        <.panels snapshot={@snapshot} />
        <.storage reading={@reading} snapshot={@snapshot} />

        <.card title="Solakon-Verlauf" subtitle="Leistung in Watt">
          <.live_component
            module={SolakonHistoryComponent}
            id="solakon_history"
            range={@history_range}
            page={:solakon}
            refresh={@history_refresh}
          />
        </.card>

        <.async_result :let={economics} assign={@economics}>
          <:loading><.pending title="Wirtschaftlichkeit" /></:loading>
          <:failed><.failed title="Wirtschaftlichkeit" /></:failed>
          <.overview_card result={economics} />
        </.async_result>

        <.async_result :let={calendar} assign={@sun_calendar}>
          <:loading><.pending title="Sonnenkalender" /></:loading>
          <:failed><.failed title="Sonnenkalender" /></:failed>
          <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">
            Sonnenkalender {calendar.year}
          </h2>
          <.sun_calendar calendar={calendar} />
        </.async_result>

        <.async_result :let={report} assign={@shading}>
          <:loading><.pending title="Ausbeute" /></:loading>
          <:failed><.failed title="Ausbeute" /></:failed>
          <.shading report={report} />
        </.async_result>
      </div>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true

  defp pending(assigns) do
    ~H"""
    <.card title={@title} data-async="loading">
      <p class="small text-body-secondary mb-0">Wird berechnet …</p>
    </.card>
    """
  end

  attr :title, :string, required: true

  defp failed(assigns) do
    ~H"""
    <.card title={@title} data-async="failed">
      <p class="small text-danger mb-0">Konnte nicht berechnet werden.</p>
    </.card>
    """
  end
end
