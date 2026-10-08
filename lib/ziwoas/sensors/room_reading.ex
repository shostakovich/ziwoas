defmodule Ziwoas.Sensors.RoomReading do
  @moduledoc """
  A room's reading per quantity, chosen when it is read (CONTEXT.md, "Room air"): the lead
  sensor's value while its newest reading is fresh and carries the quantity, else the next
  sensor's in rank order. A SEN66 is fresh for 3 minutes, a SwitchBot sensor for 30.
  """
  alias Ziwoas.Config.Sensor
  alias Ziwoas.Sensors.{DeviceStatus, Reading}

  @quantities [
    :co2,
    :pm1_0,
    :pm2_5,
    :pm4_0,
    :pm10,
    :voc_index,
    :nox_index,
    :temperature,
    :humidity
  ]
  @ranks %{sen66: 0, meter_pro_co2: 1, outdoor_meter: 2}
  @sen66_fresh_s 3 * 60
  @switchbot_fresh_s 30 * 60

  defstruct [:room, :lead, lead_fresh: false, stand_ins: [], device_status: [], values: %{}]

  @type quantity ::
          :co2
          | :pm1_0
          | :pm2_5
          | :pm4_0
          | :pm10
          | :voc_index
          | :nox_index
          | :temperature
          | :humidity
  @type source :: :lead | :stand_in
  @type value :: %{
          value: number,
          source: source,
          sensor_id: String.t(),
          taken_at: DateTime.t()
        }
  @type t :: %__MODULE__{
          room: String.t(),
          lead: Sensor.t(),
          stand_ins: [Sensor.t()],
          lead_fresh: boolean,
          device_status: [DeviceStatus.flag()],
          values: %{quantity => value | nil}
        }
  @type point :: %{
          at: DateTime.t(),
          value: number | nil,
          source: source | nil,
          sensor_id: String.t() | nil
        }

  @spec quantities() :: [quantity]
  def quantities, do: @quantities

  @spec measures(Sensor.t()) :: [quantity]
  def measures(%Sensor{type: :sen66}), do: @quantities
  def measures(%Sensor{type: :meter_pro_co2}), do: [:co2, :temperature, :humidity]
  def measures(%Sensor{type: :outdoor_meter}), do: [:temperature, :humidity]

  @spec fresh_s(Sensor.t()) :: pos_integer
  def fresh_s(%Sensor{type: :sen66}), do: @sen66_fresh_s
  def fresh_s(%Sensor{}), do: @switchbot_fresh_s

  @doc "Whether `reading` still counts for `sensor` at `now`; the one freshness rule."
  @spec fresh?(Sensor.t(), Reading.t() | nil, DateTime.t()) :: boolean
  def fresh?(_sensor, nil, _now), do: false

  def fresh?(sensor, %Reading{taken_at: taken_at}, now),
    do: DateTime.diff(now, taken_at, :microsecond) <= fresh_s(sensor) * 1_000_000

  @doc "How far back a series must read to know the room's state at its start."
  @spec lookback_s() :: pos_integer
  def lookback_s, do: max(@sen66_fresh_s, @switchbot_fresh_s)

  @doc "The room's sensors, lead first; a SEN66 leads before a Meter Pro CO₂."
  @spec ranked([Sensor.t()], String.t()) :: [Sensor.t()]
  def ranked(sensors, room) do
    sensors
    |> Enum.filter(&(&1.room == room))
    |> Enum.sort_by(&Map.fetch!(@ranks, &1.type))
  end

  @spec select(String.t(), [Sensor.t(), ...], %{String.t() => Reading.t()}, DateTime.t()) :: t
  def select(room, [lead | stand_ins] = ranked, newest, now) do
    lead_reading = newest[lead.id]
    lead_fresh = fresh?(lead, lead_reading, now)

    %__MODULE__{
      room: room,
      lead: lead,
      stand_ins: stand_ins,
      lead_fresh: lead_fresh,
      device_status: if(lead_fresh, do: DeviceStatus.flags(lead_reading.device_status), else: []),
      values: values(ranked, newest, now)
    }
  end

  @doc """
  The room reading at each instant something changed between `from` and `to`: a reading
  arrived or a sensor's newest reading went stale. `readings` are the room's sensors'
  readings from `lookback_s/0` before `from` to `to`, oldest first. A point repeats no
  earlier point's source reading; a `nil` value marks a gap.
  """
  @spec series([Sensor.t(), ...], [Reading.t()], DateTime.t(), DateTime.t()) ::
          %{quantity => [point]}
  def series(ranked, readings, from, to) do
    instants = instants(ranked, readings, from, to)

    {snapshots, _state} =
      Enum.map_reduce(instants, {readings, %{}}, fn at, {pending, newest} ->
        {pending, newest} = advance(pending, newest, at)
        {{at, values(ranked, newest, at)}, {pending, newest}}
      end)

    Map.new(@quantities, fn quantity ->
      {quantity, points(snapshots, quantity)}
    end)
  end

  defp values([lead | _] = ranked, newest, now) do
    Map.new(@quantities, fn quantity ->
      {quantity, Enum.find_value(ranked, &value(&1, newest[&1.id], quantity, lead, now))}
    end)
  end

  defp value(_sensor, nil, _quantity, _lead, _now), do: nil

  defp value(sensor, reading, quantity, lead, now) do
    case Map.fetch!(reading, quantity) do
      nil ->
        nil

      number ->
        if fresh?(sensor, reading, now),
          do: %{
            value: number,
            source: if(sensor.id == lead.id, do: :lead, else: :stand_in),
            sensor_id: sensor.id,
            taken_at: reading.taken_at
          }
    end
  end

  defp instants(ranked, readings, from, to) do
    fresh_s = Map.new(ranked, &{&1.id, fresh_s(&1)})

    stale =
      readings
      |> Enum.group_by(& &1.device_id)
      |> Enum.flat_map(fn {id, own} -> stale_instants(own, Map.fetch!(fresh_s, id)) end)

    [from | Enum.map(readings, & &1.taken_at)]
    |> Enum.concat(stale)
    |> Enum.filter(&(DateTime.compare(&1, from) != :lt and DateTime.compare(&1, to) != :gt))
    |> Enum.sort(DateTime)
    |> Enum.dedup()
  end

  # The second after a reading's freshness ends, unless a newer one of its sensor came first.
  defp stale_instants(own, fresh_s) do
    own
    |> Enum.zip(Enum.drop(own, 1) ++ [nil])
    |> Enum.flat_map(fn {reading, next} ->
      stale_at = DateTime.add(reading.taken_at, fresh_s + 1, :second)

      if is_nil(next) or DateTime.compare(next.taken_at, stale_at) == :gt,
        do: [stale_at],
        else: []
    end)
  end

  defp advance([reading | rest] = pending, newest, at) do
    if DateTime.compare(reading.taken_at, at) == :gt,
      do: {pending, newest},
      else: advance(rest, Map.put(newest, reading.device_id, reading), at)
  end

  defp advance([], newest, _at), do: {[], newest}

  defp points(snapshots, quantity) do
    snapshots
    |> Enum.map(fn {at, values} -> {at, values[quantity]} end)
    |> Enum.dedup_by(fn {_at, value} -> value && {value.sensor_id, value.taken_at} end)
    |> Enum.map(fn
      {at, nil} ->
        %{at: at, value: nil, source: nil, sensor_id: nil}

      {at, value} ->
        %{at: at, value: value.value, source: value.source, sensor_id: value.sensor_id}
    end)
  end
end
