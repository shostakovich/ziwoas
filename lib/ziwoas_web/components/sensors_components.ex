defmodule ZiwoasWeb.SensorsComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Sensors
  alias ZiwoasWeb.Charts.Categories

  # The CO₂ chart's threshold lines take these, so each sensor keeps one colour on all three charts.
  @chart_semantic [:warning, :danger]

  attr :sensors, :list, required: true
  attr :latest, :map, required: true
  attr :now, DateTime, required: true
  attr :level, :integer, default: 2, doc: "the chart cards' heading level"

  def sensor_cards(assigns) do
    ~H"""
    <div class="setzkasten-stat-grid grid gap-3 sm:grid-cols-2 md:gap-6 lg:grid-cols-3">
      <.sensor_card
        :for={sensor <- @sensors}
        sensor={sensor}
        reading={@latest[sensor.id]}
        now={@now}
      />
    </div>
    <.charts sensors={@sensors} level={@level} />
    """
  end

  attr :sensors, :list, required: true
  attr :latest, :map, required: true

  def battery_warning(assigns) do
    names =
      for sensor <- assigns.sensors,
          reading = assigns.latest[sensor.id],
          Sensors.battery_low?(reading),
          do: sensor.name

    assigns = assign(assigns, :names, Enum.join(names, ", "))

    ~H"""
    <.alert
      :if={@names != ""}
      id="battery-warning"
      tone={:warning}
      icon="battery-low"
      title="Batterie schwach"
    >
      {@names}
    </.alert>
    """
  end

  attr :sensor, :map, required: true
  attr :reading, :map, default: nil, doc: "the sensor's newest reading"
  attr :now, DateTime, required: true

  def sensor_card(assigns) do
    reading = assigns.reading
    co2 = if assigns.sensor.type == :meter_pro_co2 && reading, do: reading.co2

    assigns =
      assign(assigns,
        co2: co2,
        temperature: reading && reading.temperature,
        note:
          if(reading,
            do:
              join_meta([
                reading.humidity && "Luftfeuchte #{number(reading.humidity, unit: "%")}",
                co2 && number(co2, unit: "ppm"),
                age_label(reading, assigns.now)
              ]),
            else: "Keine Daten"
          )
      )

    ~H"""
    <.stat
      id={"sensor-#{@sensor.id}"}
      label={@sensor.name}
      value={number(@temperature, precision: 1)}
      unit={@temperature && "°C"}
      desc={@note}
    >
      <:figure :if={@co2} label={co2_label(@co2)}><.co2_gauge ppm={@co2} /></:figure>
    </.stat>
    """
  end

  @doc "How long ago a reading, or a room reading's value, was taken; it never breaks inside."
  @spec age_label(%{taken_at: DateTime.t()} | nil, DateTime.t()) :: String.t()
  def age_label(taken, now) do
    case Sensors.age_s(taken, now) do
      nil -> "—"
      seconds when seconds < 60 -> "vor\u00A0#{max(seconds, 0)}\u00A0s"
      seconds when seconds < 3600 -> "vor\u00A0#{div(seconds, 60)}\u00A0Min"
      seconds -> "vor\u00A0#{div(seconds, 3600)}\u00A0h"
    end
  end

  attr :sensors, :list, required: true
  attr :level, :integer, default: 2

  def charts(assigns) do
    co2_sensors = Enum.filter(assigns.sensors, &(&1.type == :meter_pro_co2))

    assigns =
      assign(assigns,
        co2_sensors: co2_sensors,
        legend: legend_items(assigns.sensors, assigns.sensors),
        co2_legend: legend_items(assigns.sensors, co2_sensors)
      )

    ~H"""
    <div id="sensors_chart" class="grid gap-3 md:grid-cols-2 md:gap-6">
      <.chart_card
        :if={@co2_sensors != []}
        id="sensors-co2"
        class="md:col-span-2"
        title="CO₂"
        subtitle={chart_subtitle("ppm", @co2_sensors)}
        summary="CO₂ der letzten 24 Stunden"
        hook="SensorsChart"
        level={@level}
        hook_attrs={%{"data-series" => "co2"}}
        height={:lg}
      >
        <:legend :if={length(@co2_sensors) > 1}><.legend items={@co2_legend} /></:legend>
      </.chart_card>
      <.chart_card
        id="sensors-temperature"
        title="Temperatur"
        subtitle={chart_subtitle("°C", @sensors)}
        summary="Temperatur der letzten 24 Stunden"
        hook="SensorsChart"
        level={@level}
        hook_attrs={%{"data-series" => "temperature"}}
      >
        <:legend :if={length(@sensors) > 1}><.legend items={@legend} /></:legend>
      </.chart_card>
      <.chart_card
        id="sensors-humidity"
        title="Luftfeuchte"
        subtitle={chart_subtitle("%", @sensors)}
        summary="Luftfeuchte der letzten 24 Stunden"
        hook="SensorsChart"
        level={@level}
        hook_attrs={%{"data-series" => "humidity"}}
      >
        <:legend :if={length(@sensors) > 1}><.legend items={@legend} /></:legend>
      </.chart_card>
    </div>
    """
  end

  # Ranked across all sensors, as the hook's tonesByOrder is, so a sensor keeps its colour.
  defp legend_items(sensors, shown) do
    shown
    |> Enum.map(&{&1.id, &1.name})
    |> Categories.legend(Enum.map(sensors, & &1.id), @chart_semantic)
    |> Enum.map(&Map.put(&1, :marker, :line))
  end

  @spec chart_data([map], [map]) :: %{
          temperature: [map],
          humidity: [map],
          co2: [map],
          co2_thresholds: [pos_integer]
        }
  def chart_data(sensors, readings) do
    grouped = Enum.group_by(readings, & &1.device_id)
    co2_sensors = Enum.filter(sensors, &(&1.type == :meter_pro_co2))

    %{
      temperature: series(grouped, sensors, :temperature),
      humidity: series(grouped, sensors, :humidity),
      co2: series(grouped, co2_sensors, :co2),
      co2_thresholds: [Sensors.co2_warn_ppm(), Sensors.co2_bad_ppm()]
    }
  end

  defp series(grouped, sensors, field) do
    for sensor <- sensors do
      points =
        for reading <- Map.get(grouped, sensor.id, []),
            value = Map.fetch!(reading, field),
            not is_nil(value),
            do: [DateTime.to_unix(reading.taken_at, :millisecond), value]

      %{device_id: sensor.id, name: sensor.name, points: points}
    end
  end

  defp chart_subtitle(unit, [sensor]), do: join_meta([unit, sensor.name])
  defp chart_subtitle(unit, _sensors), do: unit

  @min_ppm 400
  @max_ppm 2000
  @center 52
  @radius 40
  @band 4
  @current_band 7
  # A hairline of the surface between neighbouring zones.
  @gap_share 0.006
  @level_labels [good: "gut", warn: "erhöht", bad: "hoch"]
  @zone_classes %{good: "fill-success", warn: "fill-warning", bad: "fill-error"}

  @spec co2_label(number) :: String.t()
  def co2_label(ppm),
    do: "CO₂ #{number(ppm, unit: "ppm")}, #{@level_labels[Sensors.co2_level(ppm)]}"

  attr :ppm, :integer, required: true
  attr :class, :any, default: "w-26"

  def co2_gauge(assigns) do
    ppm = assigns.ppm
    level = Sensors.co2_level(ppm)

    assigns =
      assign(assigns,
        zones: zones(level),
        needle_angle: fixed(share(ppm) * 180),
        center: @center,
        needle_end: @center - @radius + @current_band + 3
      )

    ~H"""
    <div class={["co2-gauge shrink-0", @class]}>
      <svg class="block h-auto w-full" viewBox="0 0 104 61">
        <path
          :for={zone <- @zones}
          class={["co2-gauge-zone", zone.class]}
          data-current={zone.current && "true"}
          data-level={zone.level}
          d={zone.path}
        />
        <g class="co2-gauge-needle" transform={"rotate(#{@needle_angle} #{@center} #{@center})"}>
          <line
            class="stroke-base-content"
            x1={@center}
            y1={@center}
            x2={@needle_end}
            y2={@center}
            stroke-width="3.5"
            stroke-linecap="round"
          />
        </g>
        <circle class="fill-base-content" cx={@center} cy={@center} r="5" />
      </svg>
    </div>
    """
  end

  defp zones(current) do
    bounds = [@min_ppm, Sensors.co2_warn_ppm(), Sensors.co2_bad_ppm(), @max_ppm]
    ranges = Enum.chunk_every(bounds, 2, 1, :discard)
    last = length(ranges) - 1

    for {{{level, _label}, [from, to]}, index} <-
          Enum.with_index(Enum.zip(@level_labels, ranges)) do
      band = if level == current, do: @current_band, else: @band
      start = share(from) + if(index > 0, do: @gap_share, else: 0)
      stop = share(to) - if(index < last, do: @gap_share, else: 0)

      %{
        level: level,
        class: @zone_classes[level],
        current: level == current,
        path: sector(start, stop, @radius - band, @radius + band)
      }
    end
  end

  defp sector(from, to, inner, outer) do
    "M #{point(from, outer)} A #{outer} #{outer} 0 0 1 #{point(to, outer)} " <>
      "L #{point(to, inner)} A #{inner} #{inner} 0 0 0 #{point(from, inner)} Z"
  end

  defp point(at, radius) do
    angle = :math.pi() * (1 - at)

    fixed(@center + radius * :math.cos(angle)) <>
      " " <> fixed(@center - radius * :math.sin(angle))
  end

  defp fixed(number), do: :erlang.float_to_binary(number * 1.0, decimals: 1)

  defp share(ppm),
    do: ((ppm |> max(@min_ppm) |> min(@max_ppm)) - @min_ppm) / (@max_ppm - @min_ppm)
end
