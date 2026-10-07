defmodule ZiwoasWeb.SolakonLive do
  @moduledoc """
  The PV page. It listens to the dashboard's live beat: `{:dashboard_live, _}`
  and `{:solakon_reading, _}` replace the energy-flow state, the only live
  region on this page. The Solakon-Verlauf reloads itself every minute, and its
  range tabs swap it in place.

  The EPS and Auto-Regelung switches are the events `"toggle_eps"` and
  `"toggle_control"`.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.DashboardComponents
  import ZiwoasWeb.EconomicsComponents
  import ZiwoasWeb.SolakonComponents
  import ZiwoasWeb.SunChartComponents

  require Logger

  alias Ziwoas.{Clock, Config, LiveState}
  alias Ziwoas.Economics.Overview
  alias Ziwoas.Plugs.{Measurement, Roster}
  alias Ziwoas.Shading
  alias Ziwoas.Solakon.{Control, Reading, Snapshot}
  alias Ziwoas.SunCalendar
  alias ZiwoasWeb.{DashboardComponents, SolakonHistoryLive}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ziwoas.PubSub, "dashboard")
      Phoenix.PubSub.subscribe(Ziwoas.PubSub, "solakon")
      SolakonHistoryLive.schedule_refresh()
    end

    config = Config.app_config()
    now = Clock.now()
    zone = config.location.timezone
    control_enabled = config.solakon && config.solakon.control_enabled
    producer_ids = config |> Config.plug_roster() |> Roster.producer_ids()

    {:ok,
     socket
     |> assign(
       page_title: "PV",
       beat: 0,
       control_enabled: control_enabled == true,
       control_active: control_enabled == true and Control.State.active?(Control.State.current()),
       control_help: nil,
       control_error: nil,
       eps_enabled: nil,
       eps_error: nil,
       attempts: 0,
       reading: Reading.newest(),
       snapshot: Snapshot.latest(),
       sun_calendar:
         SunCalendar.Builder.build(
           config.location,
           producer_ids,
           SunCalendar.Builder.latest_year(config.location, now)
         ),
       shading: Shading.Builder.build(config.location, now),
       economics: Overview.build(Clock.today(zone))
     )
     |> assign(:live, LiveState.build(config, now))}
  end

  @impl true
  def handle_info({event, _}, socket) when event in [:dashboard_live, :solakon_reading] do
    {:noreply,
     assign(socket,
       live: LiveState.build(Config.app_config(), Clock.now()),
       beat: socket.assigns.beat + 1
     )}
  end

  def handle_info({:dashboard_summary}, socket), do: {:noreply, socket}

  def handle_info(:refresh_history, socket) do
    SolakonHistoryLive.schedule_refresh()
    {:noreply, SolakonHistoryLive.reload_history(socket, socket.assigns.history.range)}
  end

  @impl true
  def handle_params(params, _uri, socket),
    do: {:noreply, SolakonHistoryLive.reload_history(socket, params["range"])}

  @impl true
  def handle_event("toggle_eps", _params, socket) do
    desired = not eps_on?(socket.assigns)

    socket =
      case eps_switch(desired) do
        {:ok, enabled} -> assign(socket, eps_enabled: enabled == true, eps_error: nil)
        {:error, message} -> assign(socket, eps_error: message)
      end

    {:noreply, update(socket, :attempts, &(&1 + 1))}
  end

  def handle_event("toggle_control", _params, socket) do
    socket =
      case control_switch(not socket.assigns.control_active) do
        {:ok, state} ->
          active = Control.State.active?(state)

          assign(socket,
            control_active: active,
            control_help: if(active, do: "folgt dem gemessenen Verbrauch", else: "pausiert"),
            control_error: nil
          )

        {:error, message} ->
          assign(socket, control_error: message)
      end

    {:noreply, update(socket, :attempts, &(&1 + 1))}
  end

  defp eps_switch(desired) do
    if is_nil(Config.app_config().solakon) do
      {:error, "Solakon nicht konfiguriert"}
    else
      with {:error, reason} <- Control.set_eps_output(desired) do
        Logger.warning("solakon_controls: EPS switch failed: #{inspect(reason)}")
        {:error, "Schalten fehlgeschlagen"}
      end
    end
  end

  defp control_switch(desired) do
    case Control.set_active(Config.app_config(), desired) do
      {:ok, state} -> {:ok, state}
      {:error, :not_configured} -> {:error, "Solakon nicht konfiguriert"}
      {:error, :disabled} -> {:error, "in Konfiguration deaktiviert"}
    end
  end

  defp eps_on?(%{eps_enabled: nil, reading: reading}),
    do: not is_nil(reading) and reading.eps_enabled == true

  defp eps_on?(%{eps_enabled: enabled}), do: enabled

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} look={@look} current_path={@current_path} main_class="app-main-wide">
      <h1 class="h2 mb-3">PV</h1>

      <div
        id="live_freshness"
        phx-hook="LiveFreshness"
        data-threshold-s={Measurement.offline_after_s()}
        data-beat={@beat}
      >
        <.card title="Energiefluss" class="energy-flow-card" {energy_flow_hook(@live)}>
          <.energy_flow
            pv_asset="icon_sonne.webp"
            pv_alt="PV"
            battery_asset={DashboardComponents.default_battery_asset()}
          />
        </.card>

        <.status reading={@reading} snapshot={@snapshot} />
        <.controls
          reading={@reading}
          eps_enabled={@eps_enabled}
          eps_error={@eps_error}
          control_enabled={@control_enabled}
          control_active={@control_active}
          control_help={@control_help}
          control_error={@control_error}
          attempts={@attempts}
        />
        <.panels snapshot={@snapshot} />
        <.storage reading={@reading} snapshot={@snapshot} />

        <.card title="Solakon-Verlauf" subtitle="Leistung in Watt">
          <.history history={@history} path={~p"/solakon"} />
        </.card>

        <.overview_card result={@economics} />

        <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">
          Sonnenkalender {@sun_calendar.year}
        </h2>
        <.sun_calendar calendar={@sun_calendar} />

        <.shading report={@shading} />
      </div>
    </Layouts.app>
    """
  end
end
