defmodule Ziwoas.Solakon.History do
  @moduledoc """
  The Solakon-Verlauf: the snapshots of the last 24 hours, 7 or 30 days as
  chart series, the energy balance of the range and the outlet's average
  flow. An unknown range reads as 24 h.
  """
  import Ecto.Query

  alias Ziwoas.{GermanNumber, LocalDay, Repo}
  alias Ziwoas.Solakon.{Reading, Snapshot}

  # 24 h is fixed seconds; 7 and 30 days are calendar days on the local clock.
  @ranges [{"24h", {:seconds, 24 * 3600}}, {"7d", {:days, 7}}, {"30d", {:days, 30}}]
  @range_labels [{"24h", "Letzte 24 h"}, {"7d", "Letzte 7 Tage"}, {"30d", "Letzte 30 Tage"}]

  # Snapshots arrive every 2 min; a gap past this is downtime and must not inflate the outlet energy.
  @outlet_max_gap_s 300

  def range_labels, do: @range_labels

  @spec range_key(term) :: String.t()
  def range_key(key) do
    if List.keymember?(@ranges, key, 0), do: key, else: "24h"
  end

  @doc "What the history renders: the chart's series, the balance and the outlet's average."
  @spec payload(term, DateTime.t(), String.t()) :: map
  def payload(range_key, now, zone) do
    range = range_key(range_key)

    case Snapshot.in_range(from_time(range, now, zone), now) do
      [] ->
        empty_payload(range)

      rows ->
        outlets = Enum.map(rows, &outlet_power_w/1)
        outlet = outlet_energy(rows, outlets)

        %{
          range: range,
          chart: chart_payload(rows, outlets),
          balance_rows: balance_rows(rows, outlet),
          outlet_average: GermanNumber.flow(outlet.avg_w, positive: "liefert", negative: "zieht"),
          message: nil
        }
    end
  end

  @doc "Where the range starts: 24 h back, or 7 or 30 days back on the local clock."
  @spec from_time(String.t(), DateTime.t(), String.t()) :: DateTime.t()
  def from_time(range, now, zone) do
    case List.keyfind(@ranges, range, 0) do
      {_, {:seconds, seconds}} -> DateTime.add(now, -seconds)
      {_, {:days, days}} -> LocalDay.advance_days(now, -days, zone)
    end
  end

  defp empty_payload(range) do
    %{
      range: range,
      chart: %{
        times: [],
        datasets: for(label <- ["PV", "Akku", "Außensteckdose", "0 W"], do: dataset(label, []))
      },
      balance_rows: [],
      outlet_average: nil,
      message: "Keine Solakon-Historie"
    }
  end

  # The client labels axis and tooltips on the household's clock from the instants alone.
  defp chart_payload(rows, outlets) do
    %{
      times: Enum.map(rows, &epoch_ms(&1.taken_at)),
      datasets: [
        dataset("PV", Enum.map(rows, &Float.round(Snapshot.pv_power_w(&1), 1))),
        dataset("Akku", Enum.map(rows, &Float.round(to_float(&1.battery_power_w), 1))),
        dataset("Außensteckdose", Enum.map(outlets, &Float.round(&1, 1))),
        dataset("0 W", Enum.map(rows, fn _ -> 0 end))
      ]
    }
  end

  defp dataset(label, data), do: %{label: label, data: data}

  defp epoch_ms(%DateTime{} = time), do: DateTime.to_unix(time, :millisecond)

  # No active power on the snapshot: the reading nearest to it within two minutes stands in.
  defp outlet_power_w(%Snapshot{active_power_w: watts}) when not is_nil(watts),
    do: to_float(watts)

  defp outlet_power_w(%Snapshot{taken_at: taken_at}) do
    unix = DateTime.to_unix(taken_at)

    nearest =
      Repo.one(
        from r in Reading,
          where:
            r.taken_at >= ^DateTime.add(taken_at, -120) and
              r.taken_at <= ^DateTime.add(taken_at, 120),
          order_by: fragment("ABS(strftime('%s', ?) - ?)", r.taken_at, ^unix),
          limit: 1,
          select: r.active_power_w
      )

    to_float(nearest)
  end

  defp balance_rows(rows, outlet) do
    first = hd(rows)
    last = List.last(rows)
    pv = delta(first.pv_total_kwh, last.pv_total_kwh)
    charge = delta(first.battery_charge_total_kwh, last.battery_charge_total_kwh)
    discharge = delta(first.battery_discharge_total_kwh, last.battery_discharge_total_kwh)

    # No grid meter on this unit (grid_power reads 0): the outlet's integrated power stands in,
    # which is the inverter's feed/draw at the socket, not whole-house grid flow.
    max = Enum.max([pv, charge, discharge, outlet.delivered_kwh, outlet.drawn_kwh, 0.001])

    [
      row("PV-Erzeugung", pv, max, "solar"),
      row("Akku geladen", charge, max, "battery"),
      row("Akku entladen", discharge, max, "battery"),
      row("Ins Hausnetz geliefert", outlet.delivered_kwh, max, "grid"),
      row("Aus Hausnetz gezogen", outlet.drawn_kwh, max, "grid")
    ]
  end

  defp outlet_energy(rows, outlets) do
    {delivered_ws, drawn_ws, total_s} =
      [rows, outlets]
      |> Enum.zip()
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce({0.0, 0.0, 0.0}, fn [{a, pa}, {b, pb}], {delivered, drawn, total} ->
        dt = DateTime.diff(b.taken_at, a.taken_at, :microsecond) / 1_000_000

        if dt > 0 do
          dt = min(dt, @outlet_max_gap_s)
          {pos_ws, neg_ws} = segment_energy_ws(pa, pb, dt)
          {delivered + pos_ws, drawn + neg_ws, total + dt}
        else
          {delivered, drawn, total}
        end
      end)

    signed_ws = delivered_ws - drawn_ws

    %{
      delivered_kwh: Float.round(delivered_ws / 3_600_000.0, 2),
      drawn_kwh: Float.round(drawn_ws / 3_600_000.0, 2),
      avg_w: if(total_s > 0, do: signed_ws / total_s, else: 0.0)
    }
  end

  # A segment straddling zero splits at the crossing: averaging its ends would cancel both directions.
  defp segment_energy_ws(pa, pb, dt) do
    cond do
      pa >= 0 and pb >= 0 ->
        {(pa + pb) / 2.0 * dt, 0.0}

      pa <= 0 and pb <= 0 ->
        {0.0, -(pa + pb) / 2.0 * dt}

      true ->
        f = pa / (pa - pb)

        {pos_peak, pos_t, neg_peak, neg_t} =
          if pa > 0, do: {pa, f * dt, -pb, (1 - f) * dt}, else: {pb, (1 - f) * dt, -pa, f * dt}

        {0.5 * pos_peak * pos_t, 0.5 * neg_peak * neg_t}
    end
  end

  defp delta(first, last), do: Float.round(max(to_float(last) - to_float(first), 0.0), 2)

  defp row(label, kwh, max, role) do
    %{
      label: label,
      value: GermanNumber.format(kwh, precision: 2, unit: "kWh"),
      share: Float.round(kwh / max * 100, 1),
      role: role
    }
  end

  defp to_float(nil), do: 0.0
  defp to_float(value), do: value * 1.0
end
