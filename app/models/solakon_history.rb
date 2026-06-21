class SolakonHistory
  RANGES = {
    "24h" => 24.hours,
    "7d" => 7.days,
    "30d" => 30.days
  }.freeze

  def initialize(range_key:, now: Time.current)
    @range_key = RANGES.key?(range_key) ? range_key : "24h"
    @now = now
  end

  def payload
    rows = SolakonSnapshot.in_range(from: from_time, to: @now).to_a
    return empty_payload if rows.empty?

    {
      range: @range_key,
      chart: chart_payload(rows),
      balance_rows: balance_rows(rows),
      message: nil
    }
  end

  private

  def from_time
    @now - RANGES.fetch(@range_key)
  end

  def empty_payload
    {
      range: @range_key,
      chart: {
        labels: [],
        datasets: [
          { label: "PV", data: [] },
          { label: "Akku", data: [] },
          { label: "Netz", data: [] },
          { label: "0 W", data: [] }
        ]
      },
      balance_rows: [],
      message: "Keine Solakon-Historie"
    }
  end

  def chart_payload(rows)
    {
      labels: rows.map { |row| label_for(row.taken_at) },
      datasets: [
        { label: "PV", data: rows.map { |row| (row.pv1_power_w.to_f + row.pv2_power_w.to_f).round(1) } },
        { label: "Akku", data: rows.map { |row| row.battery_power_w.to_f.round(1) } },
        { label: "Netz", data: rows.map { |row| row.grid_power_w.to_f.round(1) } },
        { label: "0 W", data: rows.map { 0 } }
      ]
    }
  end

  def label_for(time)
    @range_key == "24h" ? time.strftime("%H:%M") : time.strftime("%d.%m.")
  end

  def balance_rows(rows)
    first = rows.first
    last = rows.last
    deltas = {
      pv: delta(first.pv_total_kwh, last.pv_total_kwh),
      charge: delta(first.battery_charge_total_kwh, last.battery_charge_total_kwh),
      discharge: delta(first.battery_discharge_total_kwh, last.battery_discharge_total_kwh),
      import: delta(first.grid_import_total_kwh, last.grid_import_total_kwh),
      export: delta(first.grid_export_total_kwh, last.grid_export_total_kwh)
    }
    avg_grid_w = rows.map { |row| row.grid_power_w.to_f }.sum / rows.length
    max = [ deltas.values.max.to_f, avg_grid_w.abs / 1000.0, 0.001 ].max

    [
      row("PV-Erzeugung", deltas.fetch(:pv), max, :solar),
      row("Akku geladen", deltas.fetch(:charge), max, :battery),
      row("Akku entladen", deltas.fetch(:discharge), max, :battery),
      row("Netzbezug", deltas.fetch(:import), max, :grid),
      row("Netzeinspeisung", deltas.fetch(:export), max, :grid),
      {
        label: "Ø Netzleistung",
        value: "#{format_decimal(avg_grid_w.round)} W",
        share: ((avg_grid_w.abs / 1000.0) / max * 100).round(1),
        role: "grid"
      }
    ]
  end

  def delta(first_value, last_value)
    [ last_value.to_f - first_value.to_f, 0.0 ].max.round(2)
  end

  def row(label, kwh, max, role)
    { label: label, value: "#{format_decimal(kwh)} kWh", share: (kwh / max * 100).round(1), role: role.to_s }
  end

  def format_decimal(value)
    format("%.2f", value).sub(".", ",")
  end
end
