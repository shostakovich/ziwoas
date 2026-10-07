defmodule ZiwoasWeb.SolakonComponents do
  @moduledoc """
  The PV page's parts (`app/views/solakon/`): status, controls, panels,
  storage and the Solakon-Verlauf. The charts of the sun calendar and the
  shading report live in `ZiwoasWeb.SunChartComponents`.

  The controls render Rails' markup, `data-action`s included; with LiveView
  connected their switches send `"toggle_eps"` and `"toggle_control"` instead
  (`app.js` keeps the `solakon` Stimulus controller from PATCHing as well).
  """
  use ZiwoasWeb, :html

  import ZiwoasWeb.CoreComponents
  import ZiwoasWeb.DashboardComponents, only: [tile: 1]

  alias Ziwoas.{GermanNumber, RubyJSON, RubyNumeric}
  alias Ziwoas.Solakon.{History, Reading, Snapshot}

  # --- Solakon-Verlauf (solakon/_history) -------------------------------------

  @doc """
  The history frame. `frame_id` is Rails' `solakon_history` on the first
  render; a refresh renders it under another id, so the client replaces the
  frame and the chart controller reconnects with the new payload, as it does
  when Turbo reloads the frame.

  The range tabs keep Rails' href (the frame's source) as the fallback; with
  LiveView connected, `app.js` keeps the browser on the page and the
  `"history_range"` event swaps the history in place, as Turbo's frame
  navigation does.
  """
  attr :history, :map, required: true
  attr :frame_id, :string, default: "solakon_history"

  def history(assigns) do
    ~H"""
    <turbo-frame id={@frame_id}>
      <div
        data-controller="solakon-history"
        data-solakon-history-url-value={"/solakon/history?range=#{@history.range}"}
        data-solakon-history-range-value={@history.range}
      >
        <div
          class="btn-group btn-group-sm d-flex d-sm-inline-flex mb-3"
          role="group"
          aria-label="Zeitraum"
        >
          <a
            :for={{key, label} <- History.range_labels()}
            href={"/solakon/history?range=#{key}"}
            phx-click="history_range"
            phx-value-range={key}
            class={["btn btn-outline-primary flex-fill", key == @history.range && "active"]}
            aria-current={key == @history.range && "true"}
          ><span><span class="d-none d-sm-inline">Letzte </span>{String.replace_prefix(
            label,
            "Letzte ",
            ""
          )}</span></a>
        </div>
        <div class="chart-frame">
          <canvas data-solakon-history-target="canvas"></canvas>
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
                  style={"width: #{RubyNumeric.to_s(row.share)}%; background-color: var(--viz-#{row.role})"}
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
    </turbo-frame>
    """
  end

  # A <script> written whole: the HEEx formatter would wrap its body. ERB's
  # json_escape on top of ActiveSupport's escaping adds the line separators.
  defp payload_script(chart) do
    json =
      chart
      |> RubyJSON.encode!()
      |> String.replace(<<0x2028::utf8>>, "\\u2028")
      |> String.replace(<<0x2029::utf8>>, "\\u2029")

    Phoenix.HTML.raw(
      ~s(<script type="application/json" data-solakon-history-target="payload">#{json}</script>)
    )
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
      Enum.any?(alarms, &(RubyNumeric.to_i(&1) > 0)) or
        Enum.any?((latest && latest.bms_faults) || [], &(RubyNumeric.to_i(&1) > 0))

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
          src={"/assets/#{@battery_asset}"}
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
  The Steuerung cards. Before the first event they read as Rails renders them;
  afterwards `eps_enabled`, the help text and the error lines follow the events,
  as Rails' Stimulus controller rewrites them. `attempts` changes with every event,
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
        <article class="card h-100 solakon-control-card" data-solakon-target="epsCard">
          <div class="card-body p-3">
            <div class="stat">
              <span class="stat-label">Außensteckdose</span>
              <span class="stat-value fs-2" data-solakon-target="epsState">
                {if @eps_on, do: "An", else: "Aus"}
              </span>
              <span class="small text-body-secondary">
                Notstrom-Ausgang · <span data-solakon-target="epsPower">{@eps_power}</span>
                · <span data-solakon-target="epsVoltage">{@eps_voltage}</span>
              </span>
            </div>
            <div class="form-check form-switch mt-2 mb-0">
              <input
                type="checkbox"
                class="form-check-input"
                role="switch"
                id="solakon-eps-toggle"
                checked={@eps_on}
                data-solakon-target="epsToggle"
                data-action="change->solakon#toggleEps"
                phx-click="toggle_eps"
                phx-value-attempt={@attempts}
              />
              <label class="form-check-label" for="solakon-eps-toggle">Außensteckdose schalten</label>
            </div>
            <p
              class="small text-danger mt-2 mb-0"
              data-solakon-target="epsError"
              hidden={is_nil(@eps_error)}
            >
              {@eps_error}
            </p>
          </div>
        </article>
      </div>
      <div class="col">
        <article class="card h-100 solakon-control-card" data-solakon-target="controlCard">
          <div class="card-body p-3">
            <div class="stat">
              <span class="stat-label">Auto-Regelung</span>
              <span class="stat-value fs-2" data-solakon-target="controlState">
                {cond do
                  @control_active -> "Aktiv"
                  @control_enabled -> "Pausiert"
                  true -> "Aus"
                end}
              </span>
              <span class="small text-body-secondary" data-solakon-target="controlHelp">
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
                data-solakon-target="controlToggle"
                data-action="change->solakon#toggleControl"
                phx-click="toggle_control"
                phx-value-attempt={@attempts}
              />
              <label class="form-check-label" for="solakon-control-toggle">Auto-Regelung</label>
            </div>
            <p
              class="small text-danger mt-2 mb-0"
              data-solakon-target="controlError"
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
