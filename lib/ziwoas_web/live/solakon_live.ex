defmodule ZiwoasWeb.SolakonLive do
  @moduledoc """
  The PV page (Rails' `SolakonController#index`). Like Rails, it listens to
  the dashboard's live beat: `{:dashboard_live, _}` and `{:solakon_reading, _}`
  replace the energy-flow state, the only live region on this page. The
  Solakon-Verlauf reloads itself every minute, as its Turbo frame does, and
  its range tabs swap it in place.

  The EPS and Auto-Regelung switches are LiveView events (`"toggle_eps"`,
  `"toggle_control"`), not PATCHes: no CSRF token crosses apps. They switch only
  while Phoenix owns `solakon_control`; `/solakon`, both PATCH routes and the tasks
  `solakon_control` and `solakon_monitor` change hands together.
  """
  use ZiwoasWeb, :live_view

  import ZiwoasWeb.CoreComponents
  import ZiwoasWeb.DashboardComponents
  import ZiwoasWeb.EconomicsComponents
  import ZiwoasWeb.SolakonComponents
  import ZiwoasWeb.SunChartComponents

  require Logger

  alias Ziwoas.{Clock, Config, LiveState, Ownership}
  alias Ziwoas.Economics.Overview
  alias Ziwoas.Plugs.{Measurement, Roster}
  alias Ziwoas.Shading
  alias Ziwoas.Solakon.{Control, History, Reading, Snapshot}
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
       history: History.payload("24h", now, zone),
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
  def handle_event("history_range", %{"range" => range}, socket),
    do: {:noreply, SolakonHistoryLive.reload_history(socket, range)}

  # The two switches: what Rails' `solakon` controller did with its PATCHes,
  # as events. Only the owner of solakon_control switches (`ZiwoasWeb.Owned`'s rule).
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
    cond do
      not Ownership.acting?(:solakon_control) ->
        {:error, "Schalten fehlgeschlagen"}

      is_nil(Config.app_config().solakon) ->
        {:error, "Solakon nicht konfiguriert"}

      true ->
        with {:error, reason} <- Ziwoas.Solakon.Control.set_eps_output(desired) do
          Logger.warning("solakon_controls: EPS switch failed: #{inspect(reason)}")
          {:error, "Schalten fehlgeschlagen"}
        end
    end
  end

  defp control_switch(desired) do
    if Ownership.acting?(:solakon_control) do
      case Ziwoas.Solakon.Control.set_active(Config.app_config(), desired) do
        {:ok, state} -> {:ok, state}
        {:error, :not_configured} -> {:error, "Solakon nicht konfiguriert"}
        {:error, :disabled} -> {:error, "in Konfiguration deaktiviert"}
      end
    else
      {:error, "Umschalten fehlgeschlagen"}
    end
  end

  defp eps_on?(%{eps_enabled: nil, reading: reading}),
    do: not is_nil(reading) and reading.eps_enabled == true

  defp eps_on?(%{eps_enabled: enabled}), do: enabled

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app look={@look} current_path={@current_path} main_class="app-main-wide">
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
          <.history history={@history} />
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
