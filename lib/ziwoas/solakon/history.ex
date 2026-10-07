defmodule Ziwoas.Solakon.History do
  @moduledoc """
  The Solakon-Verlauf: the snapshots of the last 24 hours, 7 or 30 days as
  power series, the energy balance of the range and the outlet's mean power.
  An unknown range reads as 24 h. `Ziwoas.Solakon.history/3` builds it.

  Series are in W, oldest first, one value per snapshot; the outlet's power is
  positive while it delivers into the house, negative while it draws. Without
  snapshots `times` is empty and `balance` and `outlet_average_w` are nil.
  """
  import Ecto.Query

  alias Ziwoas.{LocalDay, Repo}
  alias Ziwoas.Solakon.{Reading, Snapshot}

  # 24 h is fixed seconds; 7 and 30 days are calendar days on the local clock.
  @ranges [{"24h", {:seconds, 24 * 3600}}, {"7d", {:days, 7}}, {"30d", {:days, 30}}]

  # Snapshots arrive every 2 min; a gap past this is downtime and must not inflate the outlet energy.
  @outlet_max_gap_s 300
  # How far a reading may lie from a snapshot without active power to stand in for it.
  @reading_window_s 120

  @enforce_keys [:range]
  defstruct [
    :range,
    :balance,
    :outlet_average_w,
    times: [],
    pv_w: [],
    battery_w: [],
    outlet_w: []
  ]

  @type range :: String.t()
  @type balance :: %{
          pv_kwh: float,
          charged_kwh: float,
          discharged_kwh: float,
          delivered_kwh: float,
          drawn_kwh: float
        }
  @type t :: %__MODULE__{
          range: range,
          times: [DateTime.t()],
          pv_w: [float],
          battery_w: [float],
          outlet_w: [float],
          balance: balance | nil,
          outlet_average_w: float | nil
        }

  @spec ranges() :: [range]
  def ranges, do: Enum.map(@ranges, &elem(&1, 0))

  @doc "The range a parameter names; anything unknown reads as 24h."
  @spec range(term) :: range
  def range(key) do
    if List.keymember?(@ranges, key, 0), do: key, else: "24h"
  end

  @spec build(term, DateTime.t(), String.t()) :: t
  def build(range_key, now, zone) do
    range = range(range_key)

    case snapshots(from_time(range, now, zone), now) do
      [] ->
        %__MODULE__{range: range}

      rows ->
        outlets = outlet_powers(rows)
        outlet = outlet_energy(rows, outlets)

        %__MODULE__{
          range: range,
          times: Enum.map(rows, & &1.taken_at),
          pv_w: Enum.map(rows, &Snapshot.pv_power_w/1),
          battery_w: Enum.map(rows, &to_float(&1.battery_power_w)),
          outlet_w: outlets,
          balance: balance(rows, outlet),
          outlet_average_w: outlet.avg_w
        }
    end
  end

  @doc "Where the range starts: 24 h back, or 7 or 30 days back on the local clock."
  @spec from_time(range, DateTime.t(), String.t()) :: DateTime.t()
  def from_time(range, now, zone) do
    case List.keyfind(@ranges, range, 0) do
      {_, {:seconds, seconds}} -> DateTime.add(now, -seconds)
      {_, {:days, days}} -> LocalDay.advance_days(now, -days, zone)
    end
  end

  # Both bounds inclusive, oldest first.
  defp snapshots(from, to) do
    Repo.all(
      from s in Snapshot,
        where: s.taken_at >= ^from and s.taken_at <= ^to,
        order_by: s.taken_at
    )
  end

  # No active power on a snapshot: the reading nearest to it within two minutes
  # stands in, compared in whole seconds. The readings come in one query.
  defp outlet_powers(rows) do
    readings =
      if Enum.any?(rows, &is_nil(&1.active_power_w)),
        do: readings_around(hd(rows).taken_at, List.last(rows).taken_at),
        else: []

    rows
    |> Enum.map_reduce(readings, fn
      %Snapshot{active_power_w: watts}, readings when not is_nil(watts) ->
        {to_float(watts), readings}

      %Snapshot{taken_at: taken_at}, readings ->
        since = DateTime.add(taken_at, -@reading_window_s)
        readings = Enum.drop_while(readings, &(DateTime.compare(elem(&1, 0), since) == :lt))
        {to_float(nearest(readings, taken_at)), readings}
    end)
    |> elem(0)
  end

  defp readings_around(first, last) do
    Repo.all(
      from r in Reading,
        where:
          r.taken_at >= ^DateTime.add(first, -@reading_window_s) and
            r.taken_at <= ^DateTime.add(last, @reading_window_s),
        order_by: r.taken_at,
        select: {r.taken_at, r.active_power_w}
    )
  end

  defp nearest(readings, taken_at) do
    until = DateTime.add(taken_at, @reading_window_s)
    unix = DateTime.to_unix(taken_at)

    readings
    |> Enum.take_while(&(DateTime.compare(elem(&1, 0), until) != :gt))
    |> Enum.min_by(&abs(DateTime.to_unix(elem(&1, 0)) - unix), fn -> {nil, nil} end)
    |> elem(1)
  end

  defp balance(rows, outlet) do
    first = hd(rows)
    last = List.last(rows)

    # No grid meter on this unit (grid_power reads 0): the outlet's integrated power stands in,
    # which is the inverter's feed/draw at the socket, not whole-house grid flow.
    %{
      pv_kwh: delta(first.pv_total_kwh, last.pv_total_kwh),
      charged_kwh: delta(first.battery_charge_total_kwh, last.battery_charge_total_kwh),
      discharged_kwh: delta(first.battery_discharge_total_kwh, last.battery_discharge_total_kwh),
      delivered_kwh: outlet.delivered_kwh,
      drawn_kwh: outlet.drawn_kwh
    }
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

  defp to_float(nil), do: 0.0
  defp to_float(value), do: value * 1.0
end
