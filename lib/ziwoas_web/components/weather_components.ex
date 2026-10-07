defmodule ZiwoasWeb.WeatherComponents do
  @moduledoc """
  The Wetter page's parts (`app/views/weather/_*.html.erb` and `WeatherHelper`):
  current conditions, today's hours, the next days in four segments.
  """
  use ZiwoasWeb, :html

  import ZiwoasWeb.CoreComponents

  alias Ziwoas.{RubyNumeric, Weather}
  alias Ziwoas.Weather.{Day, Icon, Segment}

  defmodule Cell do
    @moduledoc false
    defstruct [:text, :icon, :alt, :classes, emphasis: false]
  end

  @icon_labels %{
    "clear" => "klar",
    "partly-cloudy" => "teils bewölkt",
    "cloudy" => "bewölkt",
    "fog" => "Nebel",
    "wind" => "windig",
    "rain" => "Regen",
    "sleet" => "Schneeregen",
    "snow" => "Schnee",
    "hail" => "Hagel",
    "thunderstorm" => "Gewitter",
    "unknown" => "Wetter"
  }

  @condition_labels %{
    "dry" => "trocken",
    "fog" => "Nebel",
    "rain" => "Regen",
    "sleet" => "Schneeregen",
    "snow" => "Schnee",
    "hail" => "Hagel",
    "thunderstorm" => "Gewitter"
  }

  # weather.css places the rows in this order; rain, the rarest, comes last.
  @hour_units [wind: "Wind in km/h", solar: "Sonne in W/m²", rain: "Regen in mm"]
  @segment_rows [:temp, :rain, :solar]
  @windy_km_per_h 20
  @sunny_w_per_m2 400

  # --- Sections ------------------------------------------------------------------

  attr :current, :any, required: true
  attr :today, :list, required: true
  attr :days, :list, required: true

  def empty(assigns) do
    ~H"""
    <.card :if={is_nil(@current) and @today == [] and @days == []} title="Noch keine Wetterdaten">
      <p>Die Wetteransicht erscheint, sobald Bright Sky Daten geladen hat.</p>
    </.card>
    """
  end

  attr :current, :any, required: true
  attr :sensor, :any, required: true

  def current(assigns) do
    ~H"""
    <section :if={@current} class="weather-current card mb-3">
      <div class="card-body">
        <div class="row g-3 align-items-center">
          <div class="col-12 col-md d-flex align-items-center gap-3">
            <img
              class="weather-icon weather-icon-lg"
              width="82"
              height="82"
              alt={icon_label(@current.icon)}
              src={~p"/assets/#{Weather.asset_name(@current)}"}
            />
            <div class="stat">
              <span class="stat-label">Jetzt</span>
              <span class="stat-value fs-1">
                {de_number((@sensor || @current).temperature, precision: 1, unit: "°C")}
              </span>
              <span class="small text-body-secondary">{current_summary(@current, @sensor)}</span>
            </div>
          </div>
          <div class="col-12 col-md-auto">
            <ul class="list-unstyled row row-cols-4 row-cols-md-auto g-3 small text-body-secondary text-nowrap text-center text-md-start mb-0">
              <li class="col">
                <strong class="d-block text-body tabular-nums">{de_number(@current.relative_humidity)}%</strong>Luft
              </li>
              <li class="col">
                <strong class="d-block text-body tabular-nums">{de_number(@current.cloud_cover)}%</strong>Wolken
              </li>
              <li class="col">
                <strong class="d-block text-body tabular-nums">
                  {de_number(@current.precipitation || 0, precision: 1, unit: "mm")}
                </strong>Regen
              </li>
              <li class="col">
                <strong class="d-block text-body tabular-nums">{de_number(@current.pressure_msl || 0)}</strong>hPa
              </li>
            </ul>
          </div>
        </div>
      </div>
      <div class="weather-current-solar card-footer d-flex align-items-baseline gap-2">
        <span class="small fw-semibold text-uppercase text-warning-emphasis">
          <img class="weather-icon-inline" alt="" src={~p"/assets/weather_clear_day.webp"} /> Solar
        </span>
        <span class="fw-semibold tabular-nums">
          <%= if @current.daytime == "night" do %>
            Nacht
          <% else %>
            {de_number(Weather.solar_w_per_m2(@current), unit: "W/m²")}
          <% end %>
        </span>
      </div>
    </section>
    """
  end

  attr :records, :list, required: true
  attr :zone, :string, required: true

  def today(assigns) do
    assigns =
      assign(assigns, rows: hour_rows(assigns.records), units: hour_units(assigns.records))

    ~H"""
    <%= if @records != [] do %>
      <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">Heute</h2>
      <section class="weather-hour-row card mb-3" aria-label="Heute">
        <%!-- A key below takes over the card body's bottom padding. --%>
        <div class={["weather-hour-scroller card-body overflow-x-auto", @units != [] && "pb-2"]}>
          <.hour_card :for={record <- @records} record={record} rows={@rows} zone={@zone} />
        </div>
        <.hour_key units={@units} class="px-4 pb-4" />
      </section>
    <% end %>
    """
  end

  attr :days, :list, required: true
  attr :zone, :string, required: true

  def forecast(assigns) do
    ~H"""
    <%= if @days != [] do %>
      <h2 class="h6 text-uppercase text-body-secondary mt-4 mb-2">Nächste Tage</h2>
      <section class="vstack gap-3">
        <.day :for={day <- @days} day={day} zone={@zone} />
      </section>
    <% end %>
    """
  end

  attr :day, Day, required: true
  attr :zone, :string, required: true

  defp day(assigns) do
    segments = Day.segments(assigns.day)

    assigns =
      assign(assigns,
        segments: Enum.with_index(segments),
        rows: segment_rows(segments),
        iso: Date.to_iso8601(assigns.day.date),
        peak: Day.solar_peak_w_per_m2(assigns.day),
        precip: Day.precip_sum(assigns.day)
      )

    ~H"""
    <article
      class="weather-day-card card"
      data-controller="weather-segments"
      data-weather-segments-day-value={@iso}
      data-weather-segments-selected-class="active border-primary bg-primary-subtle"
    >
      <header class="card-header">
        <div class="d-flex justify-content-between align-items-baseline gap-2">
          <h3 class="h6 mb-0 text-nowrap">
            {Day.weekday_label(@day)}
            <span class="fw-normal text-body-secondary tabular-nums">{Day.date_label(@day)}</span>
          </h3>
          <div
            :if={@peak}
            class="weather-day-peak small fw-semibold text-warning-emphasis tabular-nums text-nowrap"
          >
            <img class="weather-icon-inline" alt="" src={~p"/assets/weather_clear_day.webp"} />
            Spitze {de_number(@peak, unit: "W/m²")}
          </div>
        </div>
        <div class="weather-day-summary small text-body-secondary tabular-nums">
          {de_number(Day.temp_min(@day))} – {de_number(Day.temp_max(@day), unit: "°C")}
          <%= if @precip > 0 do %>
            · Regen {de_number(@precip, precision: 1, unit: "mm")}
          <% end %>
        </div>
      </header>
      <div class="card-body">
        <div class="weather-day-segments">
          <button
            :for={{segment, idx} <- @segments}
            type="button"
            class="weather-segment btn btn-light w-100"
            data-weather-segments-target="tile"
            data-action="click->weather-segments#toggle"
            data-segment-index={idx}
            data-segment-complete={to_string(Segment.complete?(segment))}
            aria-expanded="false"
            aria-controls={"seg-#{@iso}-#{idx}"}
          >
            <span class="weather-segment-label small">{segment.label}</span>
            <img
              class="weather-segment-icon weather-icon weather-icon-md"
              width="72"
              height="72"
              loading="lazy"
              alt={icon_label(Segment.dominant_icon(segment))}
              src={~p"/assets/#{Segment.asset_name(segment)}"}
            />
            <%= for row <- @rows, cell = segment_cell(segment, row) do %>
              <.dynamic_tag
                tag_name={if cell.emphasis, do: "strong", else: "span"}
                class={["weather-segment-#{row}", "tabular-nums", cell.classes]}
              >
                {cell.text}
              </.dynamic_tag>
            <% end %>
          </button>
        </div>

        <div class="weather-day-hours" data-weather-segments-target="hours">
          <div
            :for={{segment, idx} <- @segments}
            class="weather-day-hour-row bg-body-secondary border rounded-3 mt-3"
            id={"seg-#{@iso}-#{idx}"}
            data-weather-segments-target="hourRow"
            data-segment-index={idx}
            hidden
          >
            <div class="weather-hour-scroller overflow-x-auto py-3 ps-3">
              <.hour_card
                :for={record <- segment.records}
                record={record}
                rows={hour_rows(segment.records)}
                zone={@zone}
              />
            </div>
            <.hour_key units={hour_units(segment.records)} class="px-3 pb-3" />
          </div>
        </div>
      </div>
    </article>
    """
  end

  attr :record, :any, required: true
  attr :rows, :list, required: true
  attr :zone, :string, required: true

  defp hour_card(assigns) do
    ~H"""
    <article class="weather-hour-card text-center small">
      <div class="weather-hour-time fw-semibold tabular-nums">
        {@record |> Weather.local_time(@zone) |> Calendar.strftime("%H:%M")}
      </div>
      <img
        class="weather-icon weather-icon-sm d-block mx-auto my-2"
        width="42"
        height="42"
        loading="lazy"
        alt={icon_label(@record.icon)}
        src={~p"/assets/#{Weather.asset_name(@record)}"}
      />
      <strong class="d-block fs-4 tabular-nums">{de_number(@record.temperature)}°</strong>
      <ul
        :if={@rows != []}
        class="weather-hour-extras list-unstyled mt-1 mb-0 text-body-secondary tabular-nums text-nowrap"
      >
        <%= for row <- @rows, cell = hour_cell(@record, row) do %>
          <li class={["weather-hour-#{row}", cell.classes, cell.emphasis && "fw-semibold"]}>
            <img class="weather-icon-inline" alt={cell.alt} src={~p"/assets/#{cell.icon}"} />
            {cell.text}
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
      class={"weather-hour-key list-unstyled d-flex flex-wrap column-gap-3 row-gap-0 small text-body-secondary mb-0 #{@class}"}
    >
      <li :for={unit <- @units} class="text-nowrap">{unit}</li>
    </ul>
    """
  end

  # --- WeatherHelper -------------------------------------------------------------

  def icon_label(icon), do: Map.get(@icon_labels, Icon.normalized_icon(icon), "Wetter")

  def condition_label(condition), do: Map.get(@condition_labels, condition)

  defp current_summary(current, sensor) do
    [
      condition_label(current.condition),
      "Wind #{de_number(current.wind_speed || 0, unit: "km/h")}",
      if(sensor, do: "eigener Sensor", else: "DWD")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  def hour_rows(records) do
    for {row, _unit} <- @hour_units, Enum.any?(records, &hour_cell(&1, row)), do: row
  end

  @doc "A chance of rain carries its own \"%\" and needs no key."
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
          text: de_number(wind),
          icon: "weather_wind_day.webp",
          alt: @hour_units[:wind],
          emphasis: windy,
          classes: if(windy, do: "text-body")
        }
    end
  end

  def hour_cell(%{daytime: "night"}, :solar), do: nil

  def hour_cell(record, :solar) do
    solar = Weather.solar_w_per_m2(record)

    %Cell{
      text: de_number(solar),
      icon: "weather_clear_day.webp",
      alt: @hour_units[:solar],
      emphasis: sunny?(solar),
      classes: "text-warning-emphasis"
    }
  end

  def hour_cell(record, :rain) do
    cond do
      is_number(record.precipitation) and record.precipitation > 0 ->
        %Cell{
          text: de_number(record.precipitation, precision: 1),
          icon: "weather_rain_day.webp",
          alt: @hour_units[:rain]
        }

      RubyNumeric.to_i(record.precipitation_probability) >= 30 ->
        %Cell{
          text: de_number(record.precipitation_probability, unit: "%"),
          icon: "weather_rain_day.webp",
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
          text: "#{de_number(min)} – #{de_number(Segment.temp_max(segment))}°",
          emphasis: true,
          classes: "fs-5"
        }
    end
  end

  def segment_cell(segment, :rain) do
    precip = Segment.precip_sum(segment)

    if precip > 0,
      do: %Cell{text: de_number(precip, precision: 1, unit: "mm"), classes: "small fw-normal"}
  end

  def segment_cell(segment, :solar) do
    solar = Segment.avg_solar_w_per_m2(segment)

    unless is_nil(solar) or Segment.all_night?(segment),
      do: %Cell{text: de_number(solar, unit: "W/m²"), classes: "small text-warning-emphasis"}
  end

  def segment_cell(_segment, _row), do: nil

  def windy?(km_per_h), do: RubyNumeric.to_i(km_per_h) >= @windy_km_per_h
  def sunny?(w_per_m2), do: RubyNumeric.to_i(w_per_m2) >= @sunny_w_per_m2
end
