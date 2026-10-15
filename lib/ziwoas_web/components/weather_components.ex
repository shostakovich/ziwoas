defmodule ZiwoasWeb.WeatherComponents do
  @moduledoc false
  use ZiwoasWeb, :html

  alias Ziwoas.Weather
  alias Ziwoas.Weather.{Day, Segment}
  alias ZiwoasWeb.WeatherIcon

  defmodule Cell do
    @moduledoc false
    defstruct [:text, :icon, :alt, :classes, emphasis: false, lucide: false]
  end

  @condition_labels %{
    "dry" => "trocken",
    "fog" => "Nebel",
    "rain" => "Regen",
    "sleet" => "Schneeregen",
    "snow" => "Schnee",
    "hail" => "Hagel",
    "thunderstorm" => "Gewitter"
  }

  @weekdays ~w[Montag Dienstag Mittwoch Donnerstag Freitag Samstag Sonntag]
  @segment_labels [
    night: "Nacht",
    morning: "Vormittag",
    afternoon: "Nachmittag",
    evening: "Abend"
  ]

  # weather.css places the rows in this order.
  @hour_units [wind: "Wind in km/h", solar: "Sonne in W/m²", rain: "Regen in mm"]
  @segment_rows [:temp, :rain, :solar]
  @windy_km_per_h 20
  @sunny_w_per_m2 400

  attr :current, :any, required: true
  attr :today, :list, required: true
  attr :days, :list, required: true

  def empty(assigns) do
    ~H"""
    <.empty_state
      :if={is_nil(@current) and @today == [] and @days == []}
      layout={:page}
      plush="cloud-sun-rain"
      title="Noch keine Wetterdaten"
    >
      Die Wetteransicht erscheint, sobald Bright Sky Daten geladen hat.
    </.empty_state>
    """
  end

  attr :current, :any, required: true
  attr :sensor, :any, required: true
  attr :daylight, :boolean, default: true, doc: "the sun is up now, by the clock"

  def current(assigns) do
    current = assigns.current
    night = current && (current.daytime == "night" or not assigns.daylight)

    assigns =
      assign(assigns,
        night: night,
        plush: current && WeatherIcon.current_plush_name(current, assigns.daylight),
        measures:
          current &&
            [
              {"humidity", "Luftfeuchte", number(current.relative_humidity), "%"},
              {"clouds", "Wolken", number(current.cloud_cover), "%"},
              {"rain", "Regen", number(current.precipitation || 0, precision: 1), "mm"},
              {"pressure", "Luftdruck", number(current.pressure_msl || 0), "hPa"}
            ]
      )

    ~H"""
    <.card
      :if={@current}
      id="weather-current"
      as="section"
      aria-label="Aktuelles Wetter"
    >
      <div id="weather-now" class="flex items-center justify-between gap-4">
        <div class="min-w-0">
          <p class="stat-title">Jetzt</p>
          <p class="stat-value leading-10 tabular-nums">
            {number((@sensor || @current).temperature, precision: 1)}
            <span class="text-base font-semibold text-base-content/70">°C</span>
          </p>
          <p class="text-sm text-base-content/70">{current_summary(@current, @sensor)}</p>
        </div>
        <span role="img" aria-label={icon_label(@current.icon)} class="shrink-0">
          <.plush name={@plush} size={:xl} class="size-16 sm:size-20" />
        </span>
      </div>
      <dl class="mt-3 grid grid-cols-4 gap-x-3 border-t border-base-content/10 pt-3 sm:flex sm:gap-x-10">
        <div
          :for={{key, label, value, unit} <- @measures}
          class="flex min-w-0 flex-col-reverse"
          data-measure={key}
        >
          <dt class="truncate text-xs text-base-content/70">{label}</dt>
          <dd class="font-semibold whitespace-nowrap tabular-nums">
            {value} <span class="text-xs font-medium text-base-content/70">{unit}</span>
          </dd>
        </div>
      </dl>
      <:footer>
        <p id="weather-solar" class="flex items-center gap-2">
          <.plush name={if @night, do: "weather-clear-night", else: "weather-clear-day"} size={:sm} />
          Sonne <span :if={@night} class="font-semibold text-base-content">Nacht</span>
          <span :if={!@night} class="font-semibold text-base-content tabular-nums">
            {number(Weather.solar_w_per_m2(@current), unit: "W/m²")}
          </span>
        </p>
      </:footer>
    </.card>
    """
  end

  attr :records, :list, required: true
  attr :zone, :string, required: true

  def today(assigns) do
    assigns =
      assign(assigns, rows: hour_rows(assigns.records), units: hour_units(assigns.records))

    ~H"""
    <section :if={@records != []} id="weather-today" aria-labelledby="weather-today-heading">
      <.section_heading id="weather-today-heading">Heute</.section_heading>
      <div class="border-y border-base-content/10 max-sm:-mx-4">
        <.hour_strip records={@records} rows={@rows} zone={@zone} label="Heute, Stunde für Stunde" />
      </div>
      <.hour_key units={@units} class="mt-2" />
    </section>
    """
  end

  attr :records, :list, required: true
  attr :rows, :list, required: true
  attr :zone, :string, required: true
  attr :label, :string, required: true

  defp hour_strip(assigns) do
    ~H"""
    <div
      class="weather-hour-scroller setzkasten-scroller overflow-x-auto"
      role="region"
      aria-label={@label}
      tabindex="0"
    >
      <.hour_card :for={record <- @records} record={record} rows={@rows} zone={@zone} />
    </div>
    """
  end

  attr :days, :list, required: true
  attr :zone, :string, required: true

  attr :open, :map,
    default: %{},
    doc: "the open segment's index by the day's ISO date; a tile's click sends `toggle_segment`"

  def forecast(assigns) do
    ~H"""
    <section :if={@days != []} id="weather-forecast" aria-labelledby="weather-forecast-heading">
      <.section_heading id="weather-forecast-heading">Nächste Tage</.section_heading>
      <div class="flex flex-col gap-4 md:gap-6">
        <.day :for={day <- @days} day={day} zone={@zone} open={@open} />
      </div>
    </section>
    """
  end

  attr :day, Day, required: true
  attr :zone, :string, required: true
  attr :open, :map, required: true

  defp day(assigns) do
    segments = Day.segments(assigns.day)
    iso = Date.to_iso8601(assigns.day.date)
    precip = Day.precip_sum(assigns.day)

    assigns =
      assign(assigns,
        segments: Enum.with_index(segments),
        rows: segment_rows(segments),
        iso: iso,
        selected: Map.get(assigns.open, iso),
        peak: Day.solar_peak_w_per_m2(assigns.day),
        summary:
          join_meta([
            "#{temp_range(Day.temp_min(assigns.day), Day.temp_max(assigns.day))} °C",
            precip > 0 && "Regen #{number(precip, precision: 1, unit: "mm")}"
          ])
      )

    ~H"""
    <.card
      as="article"
      id={"day-#{@iso}"}
      title={"#{weekday(@day.date)}, #{day_month(@day.date)}"}
      subtitle={@summary}
      level={3}
    >
      <:actions :if={@peak}>
        <span
          data-peak
          class="flex items-center gap-1 text-sm font-medium whitespace-nowrap text-warning-ink tabular-nums"
        >
          <.plush name="weather-clear-day" size={:sm} /> Spitze {number(@peak, unit: "W/m²")}
        </span>
      </:actions>
      <div class="weather-day-segments mt-2">
        <button
          :for={{segment, idx} <- @segments}
          type="button"
          id={"seg-#{@iso}-#{idx}-toggle"}
          class="weather-segment"
          phx-click="toggle_segment"
          phx-value-day={@iso}
          phx-value-index={idx}
          data-segment-index={idx}
          data-segment-complete={to_string(Segment.complete?(segment))}
          aria-expanded={to_string(idx == @selected)}
          aria-controls={"seg-#{@iso}-#{idx}"}
        >
          <span class="text-sm text-base-content/70">
            {segment_label(segment)}
          </span>
          <.plush
            name={WeatherIcon.plush_name(segment)}
            size={:xl}
            alt={icon_label(Segment.dominant_icon(segment))}
          />
          <%= for row <- @rows, cell = segment_cell(segment, row) do %>
            <span
              class={["weather-segment-#{row}", "tabular-nums", cell.classes]}
              data-row={row}
              data-emphasis={cell.emphasis && "true"}
            >
              {cell.text}
            </span>
          <% end %>
          <.icon name="chevron-down" class="weather-segment-chevron text-base-content/70" />
        </button>
      </div>

      <div
        :for={{segment, idx} <- @segments}
        class="mt-4 rounded-box bg-base-200 py-1"
        id={"seg-#{@iso}-#{idx}"}
        role="region"
        aria-labelledby={"seg-#{@iso}-#{idx}-toggle"}
        data-segment-index={idx}
        hidden={idx != @selected}
      >
        <.hour_strip
          records={segment.records}
          rows={hour_rows(segment.records)}
          zone={@zone}
          label={"#{weekday(@day.date)}, #{segment_label(segment)}, Stunde für Stunde"}
        />
        <.hour_key units={hour_units(segment.records)} class="px-4 pb-3" />
      </div>
    </.card>
    """
  end

  attr :record, :any, required: true
  attr :rows, :list, required: true
  attr :zone, :string, required: true

  defp hour_card(assigns) do
    ~H"""
    <article class="weather-hour-card text-center">
      <time
        class="text-sm font-medium tabular-nums"
        datetime={DateTime.to_iso8601(@record.timestamp)}
      >
        {clock(@record.timestamp, @zone)}
      </time>
      <.plush
        name={WeatherIcon.plush_name(@record)}
        size={:lg}
        alt={icon_label(@record.icon)}
        class="size-10"
      />
      <span class="text-lg font-semibold tabular-nums">
        {number(@record.temperature)}°
      </span>
      <ul
        :if={@rows != []}
        class="weather-hour-extras text-xs whitespace-nowrap text-base-content/70 tabular-nums"
      >
        <%= for row <- @rows, cell = hour_cell(@record, row) do %>
          <li
            class={["weather-hour-#{row}", cell.classes, cell.emphasis && "font-semibold"]}
            data-row={row}
            data-emphasis={cell.emphasis && "true"}
          >
            <.icon :if={cell.lucide} name={cell.icon} label={cell.alt} class="size-4 shrink-0" />
            <.plush :if={!cell.lucide} name={cell.icon} size={:sm} alt={cell.alt} />{cell.text}
          </li>
        <% end %>
      </ul>
    </article>
    """
  end

  attr :units, :list, required: true
  attr :class, :string, required: true

  # The gap separates the units, so a narrow key breaks between them without a stray dot.
  defp hour_key(assigns) do
    ~H"""
    <ul
      :if={@units != []}
      class={[
        "flex flex-wrap gap-x-4 gap-y-0.5 text-xs text-base-content/70",
        @class
      ]}
      data-hour-key
    >
      <li :for={unit <- @units} class="whitespace-nowrap">{unit}</li>
    </ul>
    """
  end

  def icon_label(icon), do: WeatherIcon.label(icon)

  def weekday(date), do: Enum.at(@weekdays, Date.day_of_week(date) - 1)

  def segment_label(%Segment{label: label}), do: Keyword.fetch!(@segment_labels, label)

  def condition_label(condition), do: Map.get(@condition_labels, condition)

  defp current_summary(current, sensor) do
    join_meta([
      condition_label(current.condition),
      "Wind #{number(current.wind_speed || 0, unit: "km/h")}",
      if(sensor, do: "eigener Sensor", else: "DWD")
    ])
  end

  def hour_rows(records) do
    for {row, _unit} <- @hour_units, Enum.any?(records, &hour_cell(&1, row)), do: row
  end

  def hour_units(records) do
    for {row, unit} <- @hour_units,
        Enum.any?(records, fn record -> match?(%Cell{alt: ^unit}, hour_cell(record, row)) end),
        do: unit
  end

  def hour_cell(record, :wind) do
    case record.wind_speed do
      nil ->
        nil

      wind ->
        windy = windy?(wind)

        %Cell{
          text: number(wind),
          icon: "wind",
          lucide: true,
          alt: @hour_units[:wind],
          emphasis: windy,
          classes: if(windy, do: "text-base-content")
        }
    end
  end

  def hour_cell(%{daytime: "night"}, :solar), do: nil

  def hour_cell(record, :solar) do
    solar = Weather.solar_w_per_m2(record)

    %Cell{
      text: number(solar),
      icon: "weather-clear-day",
      alt: @hour_units[:solar],
      emphasis: sunny?(solar),
      classes: "text-warning-ink"
    }
  end

  def hour_cell(record, :rain) do
    cond do
      is_number(record.precipitation) and record.precipitation > 0 ->
        %Cell{
          text: number(record.precipitation, precision: 1),
          icon: "weather-rain-day",
          alt: @hour_units[:rain]
        }

      at_least?(record.precipitation_probability, 30) ->
        %Cell{
          text: number(record.precipitation_probability, unit: "%"),
          icon: "weather-rain-day",
          alt: "Regenwahrscheinlichkeit"
        }

      true ->
        nil
    end
  end

  def hour_cell(_record, _row), do: nil

  def segment_rows(segments) do
    for row <- @segment_rows, Enum.any?(segments, &segment_cell(&1, row)), do: row
  end

  def segment_cell(segment, :temp) do
    case Segment.temp_min(segment) do
      nil ->
        nil

      min ->
        %Cell{
          text: "#{temp_range(min, Segment.temp_max(segment))}°",
          emphasis: true,
          classes: "text-base font-semibold"
        }
    end
  end

  def segment_cell(segment, :rain) do
    precip = Segment.precip_sum(segment)

    if precip > 0,
      do: %Cell{
        text: number(precip, precision: 1, unit: "mm"),
        classes: "text-sm text-base-content/70"
      }
  end

  def segment_cell(segment, :solar) do
    solar = Segment.avg_solar_w_per_m2(segment)

    unless is_nil(solar) or Segment.all_night?(segment),
      do: %Cell{text: number(solar, unit: "W/m²"), classes: "text-sm text-warning-ink"}
  end

  def segment_cell(_segment, _row), do: nil

  @doc "One value when both ends round alike; „bis“ after a minus, else an en dash."
  @spec temp_range(number | nil, number | nil) :: String.t()
  def temp_range(min, max) do
    {low, high} = {number(min), number(max)}

    cond do
      low == high -> low
      String.starts_with?(low, "−") -> "#{low} bis #{high}"
      true -> "#{low}–#{high}"
    end
  end

  def windy?(km_per_h), do: at_least?(km_per_h, @windy_km_per_h)
  def sunny?(w_per_m2), do: at_least?(w_per_m2, @sunny_w_per_m2)

  defp at_least?(value, threshold), do: is_number(value) and value >= threshold
end
