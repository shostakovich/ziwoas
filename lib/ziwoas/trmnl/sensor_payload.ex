defmodule Ziwoas.Trmnl.SensorPayload do
  @moduledoc """
  The merge_variables of the „Raumluft“ plugin, as the header of
  `trmnl/sensors/src/full.liquid` defines them: data only, the template words everything.

  The room is `Sensors.display_room/1`'s, as on the dashboard. A quarter hour of the CO₂
  trend counts as the stand-in's when the stand-in served CO₂ for more than half of the time
  CO₂ was known in it.
  """
  alias Ziwoas.{Clock, Config, Sensors}
  alias Ziwoas.Config.Sensor
  alias Ziwoas.Sensors.{Reading, RoomReading}
  alias Ziwoas.Trmnl.Window

  @bucket_seconds 15 * 60
  @buckets 12
  @quantities [
    co2: :co2,
    pm2_5: :pm2_5,
    pm10: :pm10,
    voc: :voc_index,
    nox: :nox_index,
    temperature: :temperature,
    humidity: :humidity
  ]
  @names Map.new(@quantities, fn {name, quantity} -> {quantity, name} end)
  @one_decimal [:pm2_5, :pm10, :temperature]
  @time_within_s 20 * 3600

  @spec build(Config.t(), DateTime.t()) :: %{merge_variables: map}
  def build(%Config{} = config, now \\ Clock.now()) do
    zone = config.location.timezone
    outdoor = Sensors.fresh_outdoor(config, now)
    {trend_start, trend_end} = Window.ending_after(now, zone, @bucket_seconds, @buckets)

    variables =
      case Sensors.display_room(config) do
        nil -> without_room(outdoor)
        room -> room_variables(config, room, outdoor, now, {trend_start, zone})
      end

    %{
      merge_variables:
        Map.merge(variables, %{
          stand: clock(now, zone),
          stand_at: DateTime.to_unix(now),
          trend_from: trend_start |> DateTime.from_unix!() |> clock(zone),
          trend_to: trend_end |> DateTime.from_unix!() |> clock(zone)
        })
    }
  end

  defp without_room(outdoor) do
    %{
      room: nil,
      source: nil,
      lead: nil,
      lead_fresh: false,
      lead_off_since: nil,
      stand_in_since: nil,
      data_until: nil,
      verdict: nil,
      verdict_because: [],
      values: Map.new(@quantities, fn {name, _quantity} -> {name, nil} end),
      levels: Map.new(@quantities, fn {name, _quantity} -> {name, nil} end),
      stand_in: [],
      co2_trend: List.duplicate(nil, @buckets),
      co2_trend_stand_in: [],
      balcony: balcony(outdoor, nil),
      hint: nil
    }
  end

  defp room_variables(config, room, outdoor, now, {trend_start, zone}) do
    reading = Sensors.room_reading(config, room, now)
    values = Map.new(@quantities, fn {name, quantity} -> {name, shown(reading, quantity)} end)
    {verdict, because} = verdict(reading)
    {trend, trend_stand_in} = co2_trend(config, room, trend_start, now)
    stand_in = for {name, quantity} <- @quantities, stand_in?(reading, quantity), do: name

    Map.merge(sinces(reading, stand_in, now, zone), %{
      room: room,
      source: source(reading),
      lead: kind(reading.lead),
      lead_fresh: reading.lead_fresh,
      verdict: verdict,
      verdict_because: because,
      values: values,
      levels: Map.new(@quantities, fn {name, quantity} -> {name, level(reading, quantity)} end),
      stand_in: stand_in,
      co2_trend: trend,
      co2_trend_stand_in: trend_stand_in,
      balcony: balcony(outdoor, values.temperature),
      hint: hint(reading, outdoor)
    })
  end

  defp shown(%RoomReading{values: values}, quantity) do
    case values[quantity] do
      nil -> nil
      %{value: value} when quantity in @one_decimal -> Float.round(value * 1.0, 1)
      %{value: value} -> round(value)
    end
  end

  defp level(%RoomReading{values: values}, quantity) do
    case values[quantity] do
      nil -> nil
      %{value: value} -> quantity |> Sensors.level(value) |> label()
    end
  end

  defp label(nil), do: nil
  defp label(atom), do: Atom.to_string(atom)

  defp stand_in?(%RoomReading{values: values}, quantity),
    do: match?(%{source: :stand_in}, values[quantity])

  defp verdict(reading) do
    case Sensors.air_verdict(reading) do
      nil -> {nil, []}
      {level, quantities} -> {label(level), Enum.map(quantities, &@names[&1])}
    end
  end

  # CO₂'s sensor, else the first sensor in rank order that serves any value.
  defp source(%RoomReading{lead: lead, stand_ins: stand_ins, values: values}) do
    ranked = [lead | stand_ins]
    serving = for %{sensor_id: id} <- Map.values(values), uniq: true, do: id
    co2_id = values.co2 && values.co2.sensor_id

    kind(Enum.find(ranked, &(&1.id == co2_id)) || Enum.find(ranked, &(&1.id in serving)))
  end

  defp kind(nil), do: nil
  defp kind(%Sensor{type: :sen66}), do: "sen66"
  defp kind(%Sensor{}), do: "switchbot"

  # The lead's last reading while it is not fresh; the stand-in's while the lead is not fresh
  # or the stand-in serves anything.
  defp sinces(%RoomReading{lead: lead} = reading, stand_in, now, zone) do
    stand_in_sensor = serving_stand_in(reading)
    newest = Sensors.latest_per_device(for %Sensor{id: id} <- [lead, stand_in_sensor], do: id)
    lead_reading = newest[lead.id]
    stand_in_reading = stand_in_sensor && newest[stand_in_sensor.id]

    %{
      lead_off_since: if(not reading.lead_fresh, do: taken_since(lead_reading, now, zone)),
      stand_in_since:
        if(not reading.lead_fresh or stand_in != [],
          do: taken_since(stand_in_reading, now, zone)
        ),
      data_until:
        [lead_reading, stand_in_reading]
        |> Enum.reject(&is_nil/1)
        |> Enum.max_by(& &1.taken_at, DateTime, fn -> nil end)
        |> taken_clock(zone)
    }
  end

  # The stand-in that serves CO₂, else any value, else the first in rank order.
  defp serving_stand_in(%RoomReading{stand_ins: stand_ins, values: values}) do
    serving = for {_quantity, %{source: :stand_in, sensor_id: id}} <- values, do: id
    co2_id = values.co2 && values.co2.sensor_id

    Enum.find(stand_ins, &(&1.id == co2_id and &1.id in serving)) ||
      Enum.find(stand_ins, &(&1.id in serving)) || List.first(stand_ins)
  end

  # As on the page: the time within 20 hours, else the day.
  defp taken_since(nil, _now, _zone), do: nil

  defp taken_since(%Reading{taken_at: taken_at}, now, zone) do
    if DateTime.diff(now, taken_at) < @time_within_s,
      do: clock(taken_at, zone),
      else: taken_at |> DateTime.shift_zone!(zone) |> Calendar.strftime("%d.%m.")
  end

  defp taken_clock(nil, _zone), do: nil
  defp taken_clock(%Reading{taken_at: taken_at}, zone), do: clock(taken_at, zone)

  defp clock(instant, zone),
    do: instant |> DateTime.shift_zone!(zone) |> Calendar.strftime("%H:%M")

  defp co2_trend(config, room, start_ts, now) do
    segments = co2_segments(config, room, DateTime.from_unix!(start_ts), now)

    buckets =
      for index <- 0..(@buckets - 1) do
        from = (start_ts + index * @bucket_seconds) * 1_000_000
        quarter_hour(segments, from, from + @bucket_seconds * 1_000_000)
      end

    {Enum.map(buckets, &elem(&1, 0)),
     for({{_mean, true}, index} <- Enum.with_index(buckets), do: index)}
  end

  # The room's CO₂ as steps {from_us, to_us, ppm, stand_in?}, each lasting until the next point.
  defp co2_segments(config, room, from, now) do
    points = Sensors.room_series(config, room, from, now).co2
    ends = Enum.map(Enum.drop(points, 1), & &1.at) ++ [now]

    for {%{value: ppm} = point, to} <- Enum.zip(points, ends), ppm != nil do
      {DateTime.to_unix(point.at, :microsecond), DateTime.to_unix(to, :microsecond), ppm,
       point.source == :stand_in}
    end
  end

  # Time-weighted mean of the quarter hour, and whether the stand-in served most of it.
  defp quarter_hour(segments, from, to) do
    overlaps =
      for {start, stop, ppm, stand_in} <- segments,
          span = min(stop, to) - max(start, from),
          span > 0,
          do: {span, ppm, stand_in}

    case overlaps do
      [] ->
        {nil, false}

      overlaps ->
        known = overlaps |> Enum.map(&elem(&1, 0)) |> Enum.sum()
        weighted = overlaps |> Enum.map(fn {span, ppm, _} -> span * ppm end) |> Enum.sum()
        by_stand_in = for({span, _ppm, true} <- overlaps, do: span) |> Enum.sum()
        {round(weighted / known), by_stand_in * 2 > known}
    end
  end

  defp balcony(nil, _room_celsius), do: nil

  defp balcony(%Reading{} = outdoor, room_celsius) do
    %{
      temperature: outdoor.temperature && Float.round(outdoor.temperature * 1.0, 1),
      humidity: outdoor.humidity && round(outdoor.humidity),
      humidity_indoors: humidity_indoors(outdoor, room_celsius)
    }
  end

  defp humidity_indoors(_outdoor, nil), do: nil

  defp humidity_indoors(outdoor, room_celsius) do
    case Sensors.humidity_at(outdoor, room_celsius) do
      nil -> nil
      humidity -> round(humidity)
    end
  end

  defp hint(reading, outdoor) do
    case Sensors.ventilation_hint(reading, outdoor) do
      nil -> nil
      effects -> Enum.map(effects, &label/1)
    end
  end
end
