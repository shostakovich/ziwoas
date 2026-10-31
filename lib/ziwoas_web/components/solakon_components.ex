defmodule ZiwoasWeb.SolakonComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Solakon
  alias Ziwoas.Solakon.{Reading, Snapshot}

  @flow_words [positive: "liefert", negative: "zieht"]
  @balance_colors %{"solar" => 2, "battery" => 3, "grid" => 1}

  attr :id, :string, required: true
  attr :history, Solakon.History, required: true
  attr :chart, :string, default: nil, doc: "the series as JSON, nil until connected"
  attr :page, :atom, values: [:solakon, :history], required: true

  def history(assigns) do
    rows = balance_rows(assigns.history)

    assigns =
      assign(assigns,
        options:
          for(
            range <- Solakon.History.ranges(),
            do: {range_label(range), range, range_path(assigns.page, range)}
          ),
        period: range_period(assigns.history.range),
        level: if(assigns.page == :solakon, do: 3, else: 2),
        empty: assigns.history.times == [],
        rows: rows,
        pv_row: Enum.find(rows, &(&1.role == "solar")),
        pair_rows: Enum.reject(rows, &(&1.role == "solar")),
        outlet_average: outlet_average(assigns.history)
      )

    ~H"""
    <.chart_card
      id={@id}
      title="Leistung"
      subtitle={"Watt · letzte #{@period}"}
      level={@level}
      hook={!@empty && "SolakonHistory"}
      hook_attrs={%{"data-chart" => @chart, "data-range" => @history.range}}
      height={if @empty, do: :auto, else: :lg}
      summary={
        if @empty,
          do: "Keine Werte, letzte #{@period}",
          else: "Leistung von PV, Akku und Außensteckdose, letzte #{@period}"
      }
    >
      <.empty_state :if={@empty} plush="sun" title="Keine Werte in diesem Zeitraum" data-role="empty">
        Der Verlauf füllt sich mit jedem Messwert, den der Wechselrichter speichert.
      </.empty_state>
      <:actions>
        <.segmented
          mode={:patch}
          value={@history.range}
          label="Zeitraum"
          size={:sm}
          options={@options}
        />
      </:actions>
      <:legend>
        <.legend :if={!@empty} items={legend_items()} class="mt-3" />
        <p :if={!@empty} class="text-xs text-base-content/70 max-w-prose mt-2">
          Über 0 W lädt der Akku und die Außensteckdose liefert ins Hausnetz, darunter entlädt
          der Akku und die Außensteckdose zieht Leistung.
        </p>
        <div
          :if={@rows != []}
          id={"#{@id}_balance"}
          class="mt-4 border-t border-base-content/10 pt-4"
        >
          <.section_heading level={@level + 1} size={:sm}>Energie im Zeitraum</.section_heading>
          <div class="grid gap-x-8 gap-y-3 md:grid-cols-2">
            <.balance_bar row={@pv_row} class="md:col-span-2" />
            <.balance_bar :for={row <- @pair_rows} row={row} />
          </div>
          <p
            :if={@outlet_average}
            class="flex justify-between gap-4 text-sm mt-4"
            data-role="outlet-average"
          >
            <span>Ø Außensteckdose</span>
            <span class="tabular-nums whitespace-nowrap">{@outlet_average}</span>
          </p>
        </div>
      </:legend>
    </.chart_card>
    """
  end

  attr :row, :map, required: true
  attr :class, :any, default: nil

  defp balance_bar(assigns) do
    ~H"""
    <.bar
      label={@row.label}
      value={@row.share}
      color={Map.fetch!(balance_colors(), @row.role)}
      show_value
      value_label={@row.value}
      class={@class}
      data-role={@row.role}
    />
    """
  end

  defp balance_colors, do: @balance_colors

  defp legend_items do
    [
      %{label: "PV", color: 2, marker: :line},
      %{label: "Akku", color: 3, marker: :line},
      %{label: "Außensteckdose", color: 1, marker: :line}
    ]
  end

  defp range_label(range) do
    case Solakon.History.span(range) do
      {:hours, hours} -> "#{hours} h"
      {:days, days} -> "#{days} Tage"
    end
  end

  defp range_period(range) do
    case Solakon.History.span(range) do
      {:hours, hours} -> "#{hours} Stunden"
      {:days, days} -> "#{days} Tage"
    end
  end

  defp range_path(:solakon, range), do: ~p"/solakon?#{[range: range]}"
  defp range_path(:history, range), do: ~p"/solakon/history?#{[range: range]}"

  @spec history_chart(Solakon.History.t()) :: map
  def history_chart(%Solakon.History{} = history) do
    %{
      times: Enum.map(history.times, &DateTime.to_unix(&1, :millisecond)),
      datasets: [
        dataset("pv", "PV", history.pv_w),
        dataset("battery", "Akku", history.battery_w),
        dataset("outlet", "Außensteckdose", history.outlet_w)
      ]
    }
  end

  defp dataset(key, label, watts),
    do: %{key: key, label: label, data: Enum.map(watts, &Float.round(&1, 1))}

  @spec balance_rows(Solakon.History.t()) :: [map]
  def balance_rows(%Solakon.History{balance: nil}), do: []

  def balance_rows(%Solakon.History{balance: balance}) do
    rows = [
      {"PV-Erzeugung", balance.pv_kwh, "solar"},
      {"Akku geladen", balance.charged_kwh, "battery"},
      {"Akku entladen", balance.discharged_kwh, "battery"},
      {"Ins Hausnetz geliefert", balance.delivered_kwh, "grid"},
      {"Aus Hausnetz gezogen", balance.drawn_kwh, "grid"}
    ]

    max = rows |> Enum.map(&elem(&1, 1)) |> Enum.max() |> max(0.001)

    for {label, kwh, role} <- rows do
      %{
        label: label,
        value: number(kwh, precision: 2, unit: "kWh"),
        share: Float.round(kwh / max * 100, 1),
        role: role
      }
    end
  end

  @spec outlet_average(Solakon.History.t()) :: String.t() | nil
  def outlet_average(%Solakon.History{outlet_average_w: nil}), do: nil
  def outlet_average(%Solakon.History{outlet_average_w: watts}), do: flow(watts, @flow_words)

  @condition_labels %{
    inverter_ready: "Wechselrichter bereit",
    inverter_running: "Wechselrichter in Betrieb",
    inverter_fault: "Wechselrichter meldet Fehler",
    island_mode: "Inselbetrieb aktiv",
    pv_overvoltage: "PV-Spannung zu hoch",
    dc_arc_fault: "DC-Lichtbogenfehler",
    pv_string_reversed: "PV-String verpolt",
    grid_loss: "Netzausfall",
    grid_voltage: "Netzspannung auffällig",
    grid_frequency: "Netzfrequenz auffällig",
    output_overcurrent: "Ausgangsstrom zu hoch",
    output_dc_component: "DC-Anteil im Ausgangsstrom zu groß",
    residual_current: "Fehlerstrom auffällig",
    grounding: "Erdung auffällig",
    low_insulation: "Isolationswiderstand zu niedrig",
    overtemperature: "Temperatur zu hoch",
    storage_fault: "Energiespeicher auffällig",
    islanding_detected: "Inselbetrieb erkannt",
    outlet_overload: "Außensteckdose überlastet",
    fan_fault: "Lüfter auffällig",
    storage_reversed: "Energiespeicher verpolt",
    meter_lost: "Zählerverbindung verloren",
    bms_unreachable: "Batteriemanagement nicht erreichbar",
    battery_warning: "Batterie-Warnung"
  }

  @spec status_messages([atom]) :: [String.t()]
  def status_messages([]), do: ["Alles ruhig"]
  def status_messages(conditions), do: Enum.map(conditions, &Map.fetch!(@condition_labels, &1))

  attr :reading, Reading, default: nil
  attr :snapshot, Snapshot, default: nil

  def status(assigns) do
    reading = assigns.reading
    latest = assigns.snapshot

    battery_power_w = reading && Reading.battery_display_power_w(reading)
    battery_soc_pct = reading && reading.battery_soc_pct
    battery_temp_c = first_value([reading, latest], :battery_temperature_c)

    {state, plush, summary} =
      battery_character(
        battery_fault?(reading, latest),
        battery_temp_c,
        battery_soc_pct,
        battery_power_w
      )

    assigns =
      assign(assigns,
        status_messages: status_messages(conditions(reading, latest)),
        battery_temp_c: battery_temp_c,
        inverter_temp_c: first_value([reading, latest], :inverter_temperature_c),
        eps_enabled: reading && reading.eps_enabled,
        battery_state: state,
        battery_plush: plush,
        battery_summary: summary
      )

    ~H"""
    <section id="solakon-status" aria-labelledby="solakon-status-heading">
      <.section_heading id="solakon-status-heading">Status</.section_heading>
      <div class="flex items-center gap-4">
        <.plush name={@battery_plush} size={:xl} data-solakon-battery-state={@battery_state} />
        <div class="min-w-0">
          <p id="solakon-status-summary" class="font-semibold">{@battery_summary}</p>
          <ul id="solakon-status-messages" class="text-sm text-base-content/70">
            <li :for={message <- @status_messages}>{message}</li>
          </ul>
        </div>
      </div>
      <.disclosure
        id="solakon-status-details"
        variant={:row}
        summary="Details"
        class="mt-4 md:max-w-md"
      >
        <.description_list>
          <:item label="Speichertemperatur (Status/Regelung)">
            {number(@battery_temp_c, precision: 1, unit: "°C")}
          </:item>
          <:item label="Wechselrichtertemperatur">
            {number(@inverter_temp_c, precision: 1, unit: "°C")}
          </:item>
          <:item label="Außensteckdose">{if @eps_enabled, do: "bereit", else: "aus"}</:item>
        </.description_list>
      </.disclosure>
    </section>
    """
  end

  defp conditions(nil, nil), do: []
  defp conditions(reading, nil), do: Solakon.conditions(reading)
  defp conditions(_reading, latest), do: Solakon.conditions(latest)

  defp battery_character(true, _temp, _soc, _power),
    do: {"fault", "battery-warning", "Akku meldet Aufmerksamkeit"}

  defp battery_character(false, temp, soc, power),
    do: temperature_character(temp) || charge_character(soc) || flow_character(power)

  defp temperature_character(nil), do: nil

  defp temperature_character(temp) do
    cond do
      temp >= Reading.hot_temp_c() -> {"hot", "battery-hot", "Akku ist warm"}
      temp <= Reading.cold_temp_c() -> {"cold", "battery-cold", "Akku ist kalt"}
      true -> nil
    end
  end

  defp charge_character(soc) do
    if not is_nil(soc) and soc <= Reading.low_soc_pct(),
      do: {"low", "battery-low", "Akku ist niedrig geladen"}
  end

  defp flow_character(power) do
    deadband = Reading.charge_deadband_w()

    cond do
      is_nil(power) -> {"normal", "battery", "Alles ruhig am Speicher"}
      power > deadband -> {"charging", "battery-charging", "Akku lädt gerade"}
      power < -deadband -> {"normal", "battery", "Akku versorgt gerade das Haus"}
      true -> {"normal", "battery", "Alles ruhig am Speicher"}
    end
  end

  defp first_value(readings, field), do: Enum.find_value(readings, &(&1 && Map.get(&1, field)))

  defp battery_fault?(reading, latest) do
    alarms = for r <- [reading, latest], r, alarm <- [r.alarm1, r.alarm2, r.alarm3], do: alarm
    bms_faults = (latest && latest.bms_faults) || []
    Enum.any?(alarms ++ bms_faults, &((&1 || 0) > 0))
  end

  attr :reading, Reading, default: nil
  attr :inverter, :boolean, required: true, doc: "whether an inverter is monitored"
  attr :eps_on, :boolean, required: true
  attr :eps_target, :boolean, default: nil, doc: "the state asked for while it switches"
  attr :eps_error, :string, default: nil
  attr :control_enabled, :boolean, required: true
  attr :control_active, :boolean, required: true
  attr :control_target, :boolean, default: nil
  attr :control_error, :string, default: nil

  def controls(assigns) do
    reading = assigns.reading

    assigns =
      assign(assigns,
        eps_state: if(assigns.eps_on, do: "An", else: "Aus"),
        eps_meta:
          join_meta([
            number(reading && reading.eps_power_w, unit: "W"),
            number(reading && reading.eps_voltage_v, precision: 1, unit: "V")
          ]),
        control_state: control_state(assigns),
        control_detail: control_detail(assigns)
      )

    ~H"""
    <section id="solakon-controls" aria-labelledby="solakon-controls-heading">
      <.section_heading id="solakon-controls-heading">Steuerung</.section_heading>
      <div class="grid gap-3 md:grid-cols-2 md:gap-6">
        <.card id="solakon-eps" title="Außensteckdose" level={3}>
          <:actions>
            <.switch
              id="solakon-eps"
              name="eps"
              event="toggle_eps"
              label="Notstrom"
              checked={shown(@eps_on, @eps_target)}
              disabled={!@inverter or !is_nil(@eps_target)}
            />
          </:actions>
          <.state_line id="solakon-eps" state={@eps_state} detail={@eps_meta} />
          <.alert :if={@eps_error} id="solakon-eps-error" tone={:error} class="mt-2">
            {@eps_error}
          </.alert>
        </.card>
        <.card id="solakon-control" title="Regelung" level={3}>
          <:actions>
            <.switch
              id="solakon-control"
              name="control"
              event="toggle_control"
              label="Auto-Regelung"
              checked={shown(@control_active, @control_target)}
              disabled={!@control_enabled or !is_nil(@control_target)}
            />
          </:actions>
          <.state_line id="solakon-control" state={@control_state} detail={@control_detail} />
          <.alert :if={@control_error} id="solakon-control-error" tone={:error} class="mt-2">
            {@control_error}
          </.alert>
        </.card>
      </div>
    </section>
    """
  end

  defp low?(soc), do: not is_nil(soc) and soc <= Reading.low_soc_pct()

  defp control_state(%{control_active: true}), do: "Aktiv"
  defp control_state(%{control_enabled: true}), do: "Pausiert"
  defp control_state(_assigns), do: "Aus"

  defp control_detail(%{control_active: true}), do: "folgt dem gemessenen Verbrauch"
  defp control_detail(%{control_enabled: true}), do: nil
  defp control_detail(_assigns), do: "in Konfiguration deaktiviert"

  attr :id, :string, required: true
  attr :state, :string, required: true
  attr :detail, :string, default: nil

  defp state_line(assigns) do
    ~H"""
    <p id={"#{@id}-meta"} class="text-sm text-base-content/70 tabular-nums">
      <span id={"#{@id}-state"} class="font-medium text-base-content">{@state}</span><span
        :if={@detail}
        data-role="detail"
      ><.meta_sep />{@detail}</span>
    </p>
    """
  end

  defp shown(state, nil), do: state
  defp shown(_state, target), do: target

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :event, :string, required: true
  attr :label, :string, required: true
  attr :checked, :boolean, required: true
  attr :disabled, :boolean, required: true

  defp switch(assigns) do
    ~H"""
    <.form for={%{}} id={"#{@id}-form"} phx-change={@event} phx-auto-recover="ignore">
      <.input
        type="toggle"
        id={"#{@id}-toggle"}
        name={@name}
        label={@label}
        checked={@checked}
        disabled={@disabled}
        bare
      />
    </.form>
    """
  end

  attr :snapshot, Snapshot, default: nil
  attr :stale, :boolean, default: false

  def panels(assigns) do
    assigns =
      assign(
        assigns,
        :panels,
        if(assigns.snapshot, do: Snapshot.panels(assigns.snapshot), else: [])
      )

    ~H"""
    <section id="solakon-panels" aria-labelledby="solakon-panels-heading">
      <.section_heading id="solakon-panels-heading">Panels</.section_heading>
      <.empty_state :if={@panels == []} title="Noch keine Panelwerte">
        Sie erscheinen mit der ersten Messung des Wechselrichters.
      </.empty_state>
      <div
        :if={@panels != []}
        class="setzkasten-stat-grid grid grid-cols-2 md:grid-cols-4 gap-3 md:gap-4"
      >
        <.stat
          :for={panel <- @panels}
          id={"solakon-panel-#{panel.index}"}
          label={"Panel #{panel.index}"}
          value={number(panel.power_w)}
          unit="W"
          desc={
            join_meta([
              number(panel.voltage_v, precision: 1, unit: "V"),
              number(panel.current_a, precision: 2, unit: "A")
            ])
          }
          size={:sm}
          stale={@stale}
        />
      </div>
    </section>
    """
  end

  attr :reading, Reading, default: nil
  attr :snapshot, Snapshot, default: nil
  attr :stale, :boolean, default: false

  def storage(assigns) do
    reading = assigns.reading
    latest = assigns.snapshot

    either = fn field ->
      (reading && Map.get(reading, field)) || (latest && Map.get(latest, field))
    end

    assigns =
      assign(assigns,
        soc: reading && reading.battery_soc_pct,
        tiles: [
          {"health", "Batterie­gesundheit", number(latest && latest.battery_health_pct), "%"},
          {"power", "Aktuelle Batterie­leistung",
           number(reading && Reading.battery_display_power_w(reading)), "W"},
          {"voltage", "Batterie­spannung", number(either.(:battery_voltage_v), precision: 1),
           "V"},
          {"current", "Batteriestrom", number(either.(:battery_current_a), precision: 2), "A"},
          {"temperature", "Speicher­temperatur",
           number(either.(:battery_temperature_c), precision: 1), "°C"},
          {"capacity", "Volle Kapazität",
           number(latest && latest.full_charge_capacity_ah, precision: 1), "Ah"}
        ]
      )

    ~H"""
    <section id="solakon-storage" aria-labelledby="solakon-storage-heading">
      <.section_heading id="solakon-storage-heading">Speicher</.section_heading>
      <div class="setzkasten-stat-grid grid grid-cols-2 md:grid-cols-4 gap-3 md:gap-4">
        <.stat
          id="solakon-storage-soc"
          label="Ladestand"
          value={number(@soc)}
          unit="%"
          size={:sm}
          stale={@stale}
          class="col-span-2"
        >
          <:meter :if={@soc}>
            <.bar
              label="Ladestand"
              value={@soc}
              color={if !low?(@soc), do: 3}
              tone={:warning}
              hide_label
              data-low={to_string(low?(@soc))}
            />
          </:meter>
        </.stat>
        <.stat
          :for={{key, label, value, unit} <- @tiles}
          id={"solakon-storage-#{key}"}
          label={label}
          value={value}
          unit={unit}
          size={:sm}
          stale={@stale}
        />
      </div>
    </section>
    """
  end
end
