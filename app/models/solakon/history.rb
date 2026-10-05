module Solakon
  class History
    RANGES = {
      "24h" => 24.hours,
      "7d" => 7.days,
      "30d" => 30.days
    }.freeze

    RANGE_LABELS = {
      "24h" => "Letzte 24 h",
      "7d" => "Letzte 7 Tage",
      "30d" => "Letzte 30 Tage"
    }.freeze

    # Snapshots arrive every 2 min; a gap past this is downtime and must not inflate the outlet energy.
    OUTLET_MAX_GAP_S = 300

    def initialize(range_key:, now: Time.current)
      @range_key = RANGES.key?(range_key) ? range_key : "24h"
      @now = now
    end

    def payload
      rows = Solakon::Snapshot.in_range(from: from_time, to: @now).to_a
      return empty_payload if rows.empty?

      outlet = outlet_energy(rows)
      {
        range: @range_key,
        chart: chart_payload(rows),
        balance_rows: balance_rows(rows, outlet),
        outlet_average: GermanNumber.flow(outlet.fetch(:avg_w), positive: "liefert", negative: "zieht"),
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
          times: [],
          datasets: [
            { label: "PV", data: [] },
            { label: "Akku", data: [] },
            { label: "Außensteckdose", data: [] },
            { label: "0 W", data: [] }
          ]
        },
        balance_rows: [],
        outlet_average: nil,
        message: "Keine Solakon-Historie"
      }
    end

    # The client labels axis and tooltips on the household's clock from the instants alone.
    def chart_payload(rows)
      {
        times: rows.map { |row| epoch_ms(row.taken_at) },
        datasets: [
          { label: "PV", data: rows.map { |row| row.pv_power_w.round(1) } },
          { label: "Akku", data: rows.map { |row| row.battery_power_w.to_f.round(1) } },
          { label: "Außensteckdose", data: rows.map { |row| outlet_power_w(row).round(1) } },
          { label: "0 W", data: rows.map { 0 } }
        ]
      }
    end

    def epoch_ms(time) = (time.to_i * 1000) + (time.usec / 1000)

    def outlet_power_w(row)
      return row.active_power_w.to_f if row.active_power_w.present?

      nearest = Solakon::Reading
        .where(taken_at: (row.taken_at - 2.minutes)..(row.taken_at + 2.minutes))
        .order(Arel.sql("ABS(strftime('%s', taken_at) - #{row.taken_at.to_i})"))
        .first
      nearest&.active_power_w.to_f
    end

    def balance_rows(rows, outlet)
      first = rows.first
      last = rows.last
      deltas = {
        pv: delta(first.pv_total_kwh, last.pv_total_kwh),
        charge: delta(first.battery_charge_total_kwh, last.battery_charge_total_kwh),
        discharge: delta(first.battery_discharge_total_kwh, last.battery_discharge_total_kwh)
      }
      # No grid meter on this unit (grid_power reads 0): the outlet's integrated power stands in,
      # which is the inverter's feed/draw at the socket, not whole-house grid flow.
      max = [ deltas.values.max, outlet.fetch(:delivered_kwh), outlet.fetch(:drawn_kwh), 0.001 ].max

      [
        row("PV-Erzeugung", deltas.fetch(:pv), max, :solar),
        row("Akku geladen", deltas.fetch(:charge), max, :battery),
        row("Akku entladen", deltas.fetch(:discharge), max, :battery),
        row("Ins Hausnetz geliefert", outlet.fetch(:delivered_kwh), max, :grid),
        row("Aus Hausnetz gezogen", outlet.fetch(:drawn_kwh), max, :grid)
      ]
    end

    def outlet_energy(rows)
      delivered_ws = 0.0
      drawn_ws = 0.0
      total_s = 0.0
      rows.each_cons(2) do |a, b|
        dt = (b.taken_at - a.taken_at).to_f
        next unless dt.positive?

        dt = [ dt, OUTLET_MAX_GAP_S ].min
        pos_ws, neg_ws = segment_energy_ws(outlet_power_w(a), outlet_power_w(b), dt)
        delivered_ws += pos_ws
        drawn_ws += neg_ws
        total_s += dt
      end

      signed_ws = delivered_ws - drawn_ws
      {
        delivered_kwh: (delivered_ws / 3_600_000.0).round(2),
        drawn_kwh: (drawn_ws / 3_600_000.0).round(2),
        avg_w: total_s.positive? ? signed_ws / total_s : 0.0
      }
    end

    # A segment straddling zero splits at the crossing: averaging its ends would cancel both directions.
    def segment_energy_ws(pa, pb, dt)
      if pa >= 0 && pb >= 0
        [ (pa + pb) / 2.0 * dt, 0.0 ]
      elsif pa <= 0 && pb <= 0
        [ 0.0, -(pa + pb) / 2.0 * dt ]
      else
        f = pa / (pa - pb)
        pos_peak, pos_t, neg_peak, neg_t =
          pa > 0 ? [ pa, f * dt, -pb, (1 - f) * dt ] : [ pb, (1 - f) * dt, -pa, f * dt ]
        [ 0.5 * pos_peak * pos_t, 0.5 * neg_peak * neg_t ]
      end
    end

    def delta(first_value, last_value)
      [ last_value.to_f - first_value.to_f, 0.0 ].max.round(2)
    end

    def row(label, kwh, max, role)
      { label: label, value: GermanNumber.format(kwh, precision: 2, unit: "kWh"), share: (kwh / max * 100).round(1), role: role.to_s }
    end
  end
end
