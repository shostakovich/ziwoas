defmodule Ziwoas.Sensors do
  @moduledoc false
  import Ecto.Query

  alias Ziwoas.{Config, Repo}
  alias Ziwoas.Sensors.{DeviceStatus, Reading, RoomReading}

  @topic inspect(__MODULE__)

  @co2_warn_ppm 1000
  @co2_bad_ppm 1400
  @level_limits %{
    co2: [@co2_warn_ppm, @co2_bad_ppm],
    pm2_5: [15, 35],
    pm10: [45, 100],
    voc_index: [150, 250],
    nox_index: [20, 150],
    humidity: [30, 40, 60, 70],
    temperature: [18, 26]
  }
  @verdict_quantities [:co2, :pm2_5, :pm10, :voc_index, :nox_index]
  @warm_room_above_c 24
  @temperature_min_difference_k 1.0
  @comfortable_humidity 40..60
  @humidity_min_difference_g_m3 0.3
  @battery_low_pct 20
  @offline_after_s 30 * 60
  @outdoor_freshness_s 30 * 60

  @spec subscribe() :: :ok | {:error, term}
  def subscribe, do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)

  @spec notify_polled(DateTime.t()) :: :ok
  def notify_polled(%DateTime{} = instant) do
    broadcast(:polled, instant)
    :ok
  end

  defp broadcast(event, payload),
    do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, @topic, {event, payload})

  @spec create_reading(String.t(), DateTime.t(), map) ::
          {:ok, Reading.t()} | {:error, Ecto.Changeset.t()}
  def create_reading(device_id, %DateTime{} = taken_at, measurements) do
    with {:ok, reading} <- device_id |> Reading.changeset(taken_at, measurements) |> Repo.insert() do
      broadcast(:reading, reading)
      {:ok, reading}
    end
  end

  @spec latest(String.t()) :: Reading.t() | nil
  def latest(device_id) do
    Repo.one(
      from r in Reading,
        where: r.device_id == ^device_id,
        order_by: [desc: r.taken_at, desc: r.id],
        limit: 1
    )
  end

  @doc "Among readings sharing the newest `taken_at`, the last one stored wins."
  @spec latest_per_device([String.t()]) :: %{String.t() => Reading.t()}
  def latest_per_device([]), do: %{}

  def latest_per_device(device_ids) do
    newest =
      from r in Reading,
        where: r.device_id in ^device_ids,
        group_by: r.device_id,
        select: %{device_id: r.device_id, taken_at: max(r.taken_at)}

    from(r in Reading,
      join: n in subquery(newest),
      on: n.device_id == r.device_id and n.taken_at == r.taken_at,
      order_by: r.id
    )
    |> Repo.all()
    |> Map.new(&{&1.device_id, &1})
  end

  @spec since([String.t()], DateTime.t()) :: [Reading.t()]
  def since(device_ids, since) do
    Repo.all(
      from r in Reading,
        where: r.device_id in ^device_ids and r.taken_at >= ^since,
        order_by: r.taken_at
    )
  end

  @doc """
  The newest outdoor reading of at most 30 minutes, from the given sensors or the config's
  outdoor meters.
  """
  @spec fresh_outdoor(Config.t() | [String.t()], DateTime.t()) :: Reading.t() | nil
  def fresh_outdoor(%Config{sensors: sensors}, now),
    do: fresh_outdoor(for(%{type: :outdoor_meter, id: id} <- sensors, do: id), now)

  def fresh_outdoor([], _now), do: nil

  def fresh_outdoor(device_ids, now) do
    since = DateTime.add(now, -@outdoor_freshness_s, :second)

    Repo.one(
      from r in Reading,
        where: r.device_id in ^device_ids and r.taken_at >= ^since,
        order_by: [desc: r.taken_at],
        limit: 1
    )
  end

  @doc "Rooms named by the config's sensors, in config order."
  @spec rooms(Config.t()) :: [String.t()]
  def rooms(%Config{sensors: sensors}),
    do: sensors |> Enum.map(& &1.room) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  @doc """
  The room the dashboard tile and the TRMNL show: the first SEN66's with a room, else the
  first room measuring CO₂; nil without either.
  """
  @spec display_room(Config.t()) :: String.t() | nil
  def display_room(%Config{sensors: sensors} = config) do
    Enum.find_value(sensors, fn
      %{type: :sen66, room: room} when is_binary(room) -> room
      _sensor -> nil
    end) || config |> rooms() |> Enum.find(&(:co2 in room_quantities(config, &1)))
  end

  @doc "What the room's sensors measure between them, in `RoomReading.quantities/0` order."
  @spec room_quantities(Config.t(), String.t()) :: [RoomReading.quantity()]
  def room_quantities(%Config{sensors: sensors}, room) do
    measured = for %{room: ^room} = sensor <- sensors, q <- RoomReading.measures(sensor), do: q
    Enum.filter(RoomReading.quantities(), &(&1 in measured))
  end

  @doc "The room's reading now; nil for a room without sensors."
  @spec room_reading(Config.t(), String.t(), DateTime.t()) :: RoomReading.t() | nil
  def room_reading(%Config{sensors: sensors}, room, now) do
    case RoomReading.ranked(sensors, room) do
      [] ->
        nil

      ranked ->
        RoomReading.select(room, ranked, latest_per_device(Enum.map(ranked, & &1.id)), now)
    end
  end

  @doc """
  The room's reading from `from` to `to`, per quantity: a list of
  `%{at: DateTime, value: number | nil, source: :lead | :stand_in | nil, sensor_id: id | nil}`,
  oldest first, one point whenever the reading changed; a `nil` value starts a gap.
  """
  @spec room_series(Config.t(), String.t(), DateTime.t(), DateTime.t()) ::
          %{RoomReading.quantity() => [RoomReading.point()]}
  def room_series(%Config{sensors: sensors}, room, from, to) do
    case RoomReading.ranked(sensors, room) do
      [] ->
        Map.new(RoomReading.quantities(), &{&1, []})

      ranked ->
        ids = Enum.map(ranked, & &1.id)
        since = DateTime.add(from, -RoomReading.lookback_s(), :second)

        readings =
          Repo.all(
            from r in Reading,
              where: r.device_id in ^ids and r.taken_at >= ^since and r.taken_at <= ^to,
              order_by: [r.taken_at, r.id]
          )

        RoomReading.series(ranked, readings, from, to)
    end
  end

  @spec device_status_flags(non_neg_integer | nil) :: [DeviceStatus.flag()]
  defdelegate device_status_flags(status), to: DeviceStatus, as: :flags

  @type level :: :good | :warn | :bad

  @doc """
  Good, warn or bad for a quantity's value. CO₂ warns from 1000 ppm and is bad above 1400;
  PM2.5 (15/35 µg/m³), PM10 (45/100), VOC (150/250) and NOx (20/150) are good up to the
  first limit and warn up to the second; humidity is good from 40 to 60 % and warns from
  30 to 70; temperature is good from 18 to 26 °C, else it warns.
  """
  @spec level(RoomReading.quantity(), number | nil) :: level | nil
  def level(quantity, value) when is_number(value) and is_map_key(@level_limits, quantity),
    do: level_of(quantity, value, Map.fetch!(@level_limits, quantity))

  def level(_quantity, _value), do: nil

  defp level_of(:co2, ppm, [_warn, bad]) when ppm > bad, do: :bad
  defp level_of(:co2, ppm, [warn, _bad]) when ppm >= warn, do: :warn
  defp level_of(:co2, _ppm, _limits), do: :good

  defp level_of(:humidity, rh, [_, low, high, _]) when rh >= low and rh <= high, do: :good
  defp level_of(:humidity, rh, [low, _, _, high]) when rh >= low and rh <= high, do: :warn
  defp level_of(:humidity, _rh, _limits), do: :bad

  defp level_of(:temperature, c, [low, high]) when c >= low and c <= high, do: :good
  defp level_of(:temperature, _c, _limits), do: :warn

  defp level_of(_quantity, value, [good, _warn]) when value <= good, do: :good
  defp level_of(_quantity, value, [_good, warn]) when value <= warn, do: :warn
  defp level_of(_quantity, _value, _limits), do: :bad

  @doc "The values where a quantity's level changes, ascending (see `level/2`)."
  @spec level_limits(RoomReading.quantity()) :: [number] | nil
  def level_limits(quantity), do: @level_limits[quantity]

  @doc """
  The worst level among the room's CO₂, PM2.5, PM10, VOC and NOx, with the quantities at
  that level; nil while none of them is known.
  """
  @spec air_verdict(RoomReading.t()) :: {level, [RoomReading.quantity()]} | nil
  def air_verdict(%RoomReading{values: values}) do
    levels =
      for quantity <- @verdict_quantities,
          %{value: value} <- [values[quantity]],
          do: {quantity, level(quantity, value)}

    case levels do
      [] ->
        nil

      levels ->
        worst = levels |> Enum.map(&elem(&1, 1)) |> Enum.max_by(&severity/1)
        {worst, for({quantity, ^worst} <- levels, do: quantity)}
    end
  end

  defp severity(:good), do: 0
  defp severity(:warn), do: 1
  defp severity(:bad), do: 2

  @doc """
  What airing the room would do against the outdoor reading: `:cools` or `:warms` when the
  room is above 24 °C and outside is at least 1 K cooler or warmer; `:dries` or `:humidifies`
  when the room's humidity is outside 40–60 % and the outside air holds over 0.3 g/m³ less
  or more water.
  nil without an outdoor reading or when there is nothing to say.
  """
  @spec ventilation_hint(RoomReading.t(), Reading.t() | nil) ::
          [:cools | :warms | :dries | :humidifies] | nil
  def ventilation_hint(%RoomReading{}, nil), do: nil

  def ventilation_hint(%RoomReading{values: values}, %Reading{} = outdoor) do
    room = %{temperature: number(values.temperature), humidity: number(values.humidity)}

    case Enum.reject(
           [temperature_effect(room, outdoor), humidity_effect(room, outdoor)],
           &is_nil/1
         ) do
      [] -> nil
      effects -> effects
    end
  end

  defp number(%{value: value}), do: value
  defp number(nil), do: nil

  defp temperature_effect(%{temperature: inside}, %Reading{temperature: outside})
       when is_number(inside) and is_number(outside) and inside > @warm_room_above_c do
    difference = Float.round((outside - inside) * 1.0, 1)

    cond do
      difference <= -@temperature_min_difference_k -> :cools
      difference >= @temperature_min_difference_k -> :warms
      true -> nil
    end
  end

  defp temperature_effect(_room, _outdoor), do: nil

  defp humidity_effect(%{temperature: t_in, humidity: rh_in}, %Reading{} = outdoor)
       when is_number(t_in) and is_number(rh_in) and is_number(outdoor.temperature) and
              is_number(outdoor.humidity) do
    if rh_in < @comfortable_humidity.first or rh_in > @comfortable_humidity.last do
      difference =
        absolute_humidity(outdoor.temperature, outdoor.humidity) -
          absolute_humidity(t_in, rh_in)

      cond do
        difference < -@humidity_min_difference_g_m3 -> :dries
        difference > @humidity_min_difference_g_m3 -> :humidifies
        true -> nil
      end
    end
  end

  defp humidity_effect(_room, _outdoor), do: nil

  @doc """
  The relative humidity (%) a reading's air would have at `celsius`, holding as much water
  per cubic metre: the balcony air brought to room temperature. nil without both values.
  """
  @spec humidity_at(Reading.t(), number) :: float | nil
  def humidity_at(%Reading{temperature: t, humidity: rh}, celsius)
      when is_number(t) and is_number(rh) and is_number(celsius),
      do: absolute_humidity(t, rh) * (273.15 + celsius) / (saturation_hpa(celsius) * 2.1674)

  def humidity_at(%Reading{}, _celsius), do: nil

  # g/m³, Magnus formula over water.
  defp absolute_humidity(celsius, relative_pct),
    do: saturation_hpa(celsius) * relative_pct * 2.1674 / (273.15 + celsius)

  defp saturation_hpa(celsius), do: 6.112 * :math.exp(17.67 * celsius / (celsius + 243.5))

  @spec co2_warn_ppm() :: pos_integer
  def co2_warn_ppm, do: @co2_warn_ppm

  @spec co2_bad_ppm() :: pos_integer
  def co2_bad_ppm, do: @co2_bad_ppm

  @spec co2_level(Reading.t() | integer | nil) :: :good | :warn | :bad | nil
  def co2_level(%Reading{co2: ppm}), do: co2_level(ppm)
  def co2_level(ppm) when is_integer(ppm), do: level(:co2, ppm)
  def co2_level(_reading), do: nil

  @spec battery_low?(Reading.t() | nil) :: boolean
  def battery_low?(%Reading{battery_pct: pct}) when is_integer(pct), do: pct <= @battery_low_pct
  def battery_low?(_reading), do: false

  @spec age_s(Reading.t() | nil, DateTime.t()) :: integer | nil
  def age_s(nil, _now), do: nil
  def age_s(%Reading{} = reading, now), do: div(age_us(reading, now), 1_000_000)

  @spec offline?(Reading.t() | nil, DateTime.t()) :: boolean
  def offline?(nil, _now), do: true
  def offline?(%Reading{} = reading, now), do: age_us(reading, now) > @offline_after_s * 1_000_000

  defp age_us(%Reading{taken_at: taken_at}, now), do: DateTime.diff(now, taken_at, :microsecond)
end
