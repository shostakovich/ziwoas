defmodule ZiwoasWeb.SolakonComponents do
  @moduledoc """
  The PV page's parts: status, controls, panels,
  storage and the Solakon-Verlauf. The charts of the sun calendar and the
  shading report live in `ZiwoasWeb.SunChartComponents`.

  The controls' switches send `"toggle_eps"` and `"toggle_control"` to the
  LiveView.
  """
  use ZiwoasWeb, :html

  import ZiwoasWeb.DashboardComponents, only: [tile: 1]

  alias Ziwoas.GermanNumber
  alias Ziwoas.Solakon.{History, Reading, Snapshot}

  # --- Solakon-Verlauf -----------------------------------------------------------

  @doc """
  The history, the `SolakonHistory` hook: it draws the chart from the payload
  island and redraws it in place whenever the LiveView renders a new one (a
  refresh, or a range tab). The canvas sits in a `phx-update="ignore"` frame,
  the payload and the range outside it. The range tabs patch `?range=` on `path`,
  so the range survives a reload and the refresh keeps it.
  """
  attr :history, :map, required: true
  attr :path, :string, required: true

  def history(assigns) do
    ~H"""
    <div id="solakon_history" phx-hook="SolakonHistory" data-range={@history.range}>
      <div
        class="btn-group btn-group-sm d-flex d-sm-inline-flex mb-3"
        role="group"
        aria-label="Zeitraum"
      >
        <.link
          :for={{key, label} <- History.range_labels()}
          patch={"#{@path}?range=#{key}"}
          replace
          class={["btn btn-outline-primary flex-fill", key == @history.range && "active"]}
          aria-current={key == @history.range && "true"}
        >
          <span class="d-none d-sm-inline">Letzte </span>{String.replace_prefix(label, "Letzte ", "")}
        </.link>
      </div>
      <div class="chart-frame" id="solakon_history_frame" phx-update="ignore">
        <canvas></canvas>
      </div>
      <p :if={@history.message} class="small text-body-secondary">{@history.message}</p>
      <p class="small text-body-secondary">
        Über 0 W: Akku lädt, Außensteckdose liefert ins Hausnetz. Unter 0 W: Akku entlädt, Außensteckdose zieht Leistung.
      </p>
      <div class="solakon-balance mt-3">
        <div
          :for={row <- @history.balance_rows}
          class="solakon-balance-row row gx-2 gy-1 align-items-center small mb-2"
          data-role={row.role}
        >
          <span class="col col-sm-4 text-truncate">{row.label}</span>
          <div class="col-12 col-sm order-last order-sm-0">
            <div class="progress" style="height: .5rem" aria-hidden="true">
              <div
                class="progress-bar"
                style={"width: #{row.share}%; background-color: var(--viz-#{row.role})"}
              >
              </div>
            </div>
          </div>
          <span class="col-auto tabular-nums text-nowrap">{row.value}</span>
        </div>
        <div
          :if={@history.outlet_average}
          class="d-flex justify-content-between gap-2 small"
          data-role="outlet-average"
        >
          <span>Ø Außensteckdose</span>
          <span class="tabular-nums text-nowrap">{@history.outlet_average}</span>
        </div>
      </div>
      {payload_script(@history.chart)}
    </div>
    """
  end

  # A <script> written whole: HEEx does not interpolate inside one. An escaped
  # "<" keeps a "</script>" in a label from closing it.
  defp payload_script(chart) do
    json = chart |> JSON.encode!() |> String.replace("<", "\\u003c")
    Phoenix.HTML.raw(~s(<script type="application/json" data-chart-payload>#{json}</script>))
  end

  # --- Status -------------------------------------------------------------------

  attr :reading, Reading, default: nil
  attr :snapshot, Snapshot, default: nil

  def status(assigns) do
    reading = assigns.reading
    latest = assigns.snapshot

    status_messages =
      cond do
        latest -> Snapshot.status_messages(latest)
        reading -> Reading.status_messages(reading)
        true -> ["Alles ruhig"]
      end

    battery_power_w = reading && Reading.battery_display_power_w(reading)
    battery_soc_pct = reading && reading.battery_soc_pct

    battery_temp_c =
      (reading && reading.battery_temperature_c) || (latest && latest.battery_temperature_c)

    alarms =
      for(r <- [reading, latest], r, do: [r.alarm1, r.alarm2, r.alarm3]) |> List.flatten()

    battery_fault =
      Enum.any?(alarms, &((&1 || 0) > 0)) or
        Enum.any?((latest && latest.bms_faults) || [], &((&1 || 0) > 0))

    {state, asset, summary} =
      battery_character(battery_fault, battery_temp_c, battery_soc_pct, battery_power_w)

    assigns =
      assign(assigns,
        status_messages: status_messages,
        battery_temp_c: battery_temp_c,
        inverter_temp_c:
          (reading && reading.inverter_temperature_c) || (latest && latest.inverter_temperature_c),
        eps_enabled: reading && reading.eps_enabled,
        battery_state: state,
        battery_asset: asset,
        battery_summary: summary
      )

    ~H"""
    <.card title="Status">
      <div class="solakon-status-figure d-flex align-items-center gap-3 mb-2">
        <img
          class="object-fit-contain flex-shrink-0"
          width="64"
          height="64"
          data-solakon-battery-state={@battery_state}
          alt=""
          src={~p"/images/#{@battery_asset}"}
        />
        <p class="solakon-status-summary fw-semibold mb-0">{@battery_summary}</p>
      </div>
      <p :for={message <- @status_messages} class="small text-body-secondary mb-1">{message}</p>
      <details class="solakon-details small text-body-secondary mt-2">
        <summary>Details</summary>
        <div class="mt-2">
          <p class="mb-1">
            Speichertemperatur (Status/Regelung) {GermanNumber.format(@battery_temp_c, precision: 1)}&nbsp;°C
          </p>
          <p class="mb-1">
            Wechselrichtertemperatur {GermanNumber.format(@inverter_temp_c, precision: 1)}&nbsp;°C
          </p>
          <p class="mb-0">Außensteckdose {if @eps_enabled, do: "bereit", else: "aus"}</p>
        </div>
      </details>
    </.card>
    """
  end

  defp battery_character(true, _temp, _soc, _power),
    do: {"fault", "solakon_battery_fault.webp", "Akku meldet Aufmerksamkeit"}

  defp battery_character(false, temp, soc, power) do
    cond do
      not is_nil(temp) and temp >= Reading.hot_temp_c() ->
        {"hot", "solakon_battery_hot.webp", "Akku ist warm"}

      not is_nil(temp) and temp <= Reading.cold_temp_c() ->
        {"cold", "solakon_battery_cold.webp", "Akku ist kalt"}

      not is_nil(soc) and soc <= Reading.low_soc_pct() ->
        {"low", "solakon_battery_low.webp", "Akku ist niedrig geladen"}

      not is_nil(power) and power > Reading.charge_deadband_w() ->
        {"charging", "solakon_battery_charging.webp", "Akku lädt gerade"}

      not is_nil(power) and power < -Reading.charge_deadband_w() ->
        {"normal", "solakon_battery_normal.webp", "Akku versorgt gerade das Haus"}

      true ->
        {"normal", "solakon_battery_normal.webp", "Alles ruhig am Speicher"}
    end
  end

  # --- Steuerung ----------------------------------------------------------------

  @doc """
  The Steuerung cards. Before the first event they read from the reading and the
  stored state; afterwards `eps_enabled`, the help text and the error lines follow
  the events. `attempts` changes with every event,
  so the switch is re-rendered and LiveView resets its `checked` state even when a
  failed switch leaves the assigns as they were.
  """
  attr :reading, Reading, default: nil
  attr :eps_enabled, :boolean, default: nil
  attr :control_enabled, :boolean, required: true
  attr :control_active, :boolean, required: true
  attr :control_help, :string, default: nil
  attr :eps_error, :string, default: nil
  attr :control_error, :string, default: nil
  attr :attempts, :integer, default: 0

  def controls(assigns) do
    reading = assigns.reading

    assigns =
      assign(assigns,
        eps_on:
          if(is_nil(assigns.eps_enabled), do: eps_enabled?(reading), else: assigns.eps_enabled),
        eps_power: GermanNumber.format(reading && reading.eps_power_w, unit: "W"),
        eps_voltage:
          GermanNumber.format(reading && reading.eps_voltage_v, precision: 1, unit: "V")
      )

    ~H"""
    <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">Steuerung</h2>
    <section class="row row-cols-1 row-cols-sm-2 g-2 mb-3">
      <div class="col">
        <article class="card h-100 solakon-control-card">
          <div class="card-body p-3">
            <div class="stat">
              <span class="stat-label">Außensteckdose</span>
              <span class="stat-value fs-2" id="solakon-eps-state">
                {if @eps_on, do: "An", else: "Aus"}
              </span>
              <span class="small text-body-secondary">
                Notstrom-Ausgang · <span>{@eps_power}</span> · <span>{@eps_voltage}</span>
              </span>
            </div>
            <div class="form-check form-switch mt-2 mb-0">
              <input
                type="checkbox"
                class="form-check-input"
                role="switch"
                id="solakon-eps-toggle"
                checked={@eps_on}
                phx-click="toggle_eps"
                phx-value-attempt={@attempts}
              />
              <label class="form-check-label" for="solakon-eps-toggle">Außensteckdose schalten</label>
            </div>
            <p
              class="small text-danger mt-2 mb-0"
              id="solakon-eps-error"
              hidden={is_nil(@eps_error)}
            >
              {@eps_error}
            </p>
          </div>
        </article>
      </div>
      <div class="col">
        <article class="card h-100 solakon-control-card">
          <div class="card-body p-3">
            <div class="stat">
              <span class="stat-label">Auto-Regelung</span>
              <span class="stat-value fs-2" id="solakon-control-state">
                {cond do
                  @control_active -> "Aktiv"
                  @control_enabled -> "Pausiert"
                  true -> "Aus"
                end}
              </span>
              <span class="small text-body-secondary" id="solakon-control-help">
                {cond do
                  @control_help -> @control_help
                  @control_enabled -> "folgt dem gemessenen Verbrauch"
                  true -> "in Konfiguration deaktiviert"
                end}
              </span>
            </div>
            <div class="form-check form-switch mt-2 mb-0">
              <input
                type="checkbox"
                class="form-check-input"
                role="switch"
                id="solakon-control-toggle"
                checked={@control_active}
                disabled={!@control_enabled}
                phx-click="toggle_control"
                phx-value-attempt={@attempts}
              />
              <label class="form-check-label" for="solakon-control-toggle">Auto-Regelung</label>
            </div>
            <p
              class="small text-danger mt-2 mb-0"
              id="solakon-control-error"
              hidden={is_nil(@control_error)}
            >
              {@control_error}
            </p>
          </div>
        </article>
      </div>
    </section>
    """
  end

  defp eps_enabled?(nil), do: false
  defp eps_enabled?(%Reading{eps_enabled: enabled}), do: enabled == true

  # --- Panels and storage -------------------------------------------------------

  attr :snapshot, Snapshot, default: nil

  def panels(assigns) do
    assigns =
      assign(
        assigns,
        :panels,
        if(assigns.snapshot, do: Snapshot.panels(assigns.snapshot), else: [])
      )

    ~H"""
    <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">Panels</h2>
    <section class="row row-cols-2 row-cols-md-4 g-2 mb-3 solakon-panel-grid">
      <.tile
        :for={panel <- @panels}
        label={panel.label}
        number={GermanNumber.format(panel.power_w, unit: "W")}
        caption={"#{GermanNumber.format(panel.voltage_v, precision: 1, unit: "V")} · #{GermanNumber.format(panel.current_a, precision: 2, unit: "A")}"}
      />
    </section>
    """
  end

  attr :reading, Reading, default: nil
  attr :snapshot, Snapshot, default: nil

  def storage(assigns) do
    reading = assigns.reading
    latest = assigns.snapshot

    either = fn field ->
      (reading && Map.get(reading, field)) || (latest && Map.get(latest, field))
    end

    assigns =
      assign(assigns,
        tiles: [
          {"Ladestand", GermanNumber.format(reading && reading.battery_soc_pct), "%"},
          {"Batterie­gesundheit", GermanNumber.format(latest && latest.battery_health_pct), "%"},
          {"Aktuelle Batterie­leistung",
           GermanNumber.format(reading && Reading.battery_display_power_w(reading)), "W"},
          {"Batterie­spannung", GermanNumber.format(either.(:battery_voltage_v), precision: 1),
           "V"},
          {"Batteriestrom", GermanNumber.format(either.(:battery_current_a), precision: 2), "A"},
          {"Speicher­temperatur",
           GermanNumber.format(either.(:battery_temperature_c), precision: 1), "°C"},
          {"Volle Kapazität",
           GermanNumber.format(latest && latest.full_charge_capacity_ah, precision: 1), "Ah"}
        ]
      )

    ~H"""
    <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">Speicher</h2>
    <section class="row row-cols-2 row-cols-md-3 g-2 mb-3 solakon-storage-grid">
      <.tile :for={{label, number, unit} <- @tiles} label={label} number={number} unit={unit} />
    </section>
    """
  end
end
