defmodule ZiwoasWeb.SensorsComponents do
  @moduledoc """
  The Sensoren page's parts (`app/views/sensors/_*.html.erb`, `SensorsHelper`
  and `Sensors::Co2GaugeComponent`): the dashboard Rails replaces on every
  sensor poll, one card per sensor, the battery warning and the chart cards
  the `sensors-chart` Stimulus controller fills from `/sensors/series`.
  """
  use ZiwoasWeb, :html

  import ZiwoasWeb.CoreComponents

  alias Ziwoas.{GermanNumber, RubyNumeric}
  alias Ziwoas.Sensors.{Reading, ReadingPresenter}

  @doc "Everything below the heading: what Rails' `sensors_dashboard` frame holds."
  attr :sensors, :list, required: true
  attr :latest, :map, required: true
  attr :now, DateTime, required: true

  def dashboard(assigns) do
    ~H"""
    <%= if @latest == %{} do %>
      <.card title="Noch keine Sensordaten">
        <p>Die Sensoransicht erscheint, sobald die SwitchBot-API Daten geliefert hat.</p>
      </.card>
    <% else %>
      <.battery_warning sensors={@sensors} latest={@latest} />
      <section
        class={[
          "row row-cols-1 g-3 mb-3",
          "row-cols-sm-#{columns(@sensors, 2)}",
          "row-cols-lg-#{columns(@sensors, 3)}"
        ]}
        aria-label="Sensoren"
      >
        <div :for={sensor <- @sensors} class="col">
          <.sensor_card sensor={sensor} reading={@latest[sensor.id]} now={@now} />
        </div>
      </section>
      <.charts sensors={@sensors} />
    <% end %>
    """
  end

  defp columns(sensors, max), do: sensors |> length() |> max(1) |> min(max)

  attr :sensors, :list, required: true
  attr :latest, :map, required: true

  def battery_warning(assigns) do
    names =
      for sensor <- assigns.sensors,
          reading = assigns.latest[sensor.id],
          ReadingPresenter.battery_low?(reading),
          do: sensor.name

    assigns = assign(assigns, :names, Enum.join(names, ", "))

    ~H"""
    <div
      :if={@names != ""}
      class="alert alert-warning d-flex align-items-center gap-3 mb-3"
      role="alert"
    >
      <img class="sensor-alert-icon" alt="" src={~p"/assets/solakon_battery_low.webp"} />
      <div><strong>Batterie schwach:</strong> {@names}</div>
    </div>
    """
  end

  attr :sensor, :map, required: true
  attr :reading, Reading, default: nil
  attr :now, DateTime, required: true

  def sensor_card(assigns) do
    assigns = assign(assigns, :co2?, assigns.sensor.type == :meter_pro_co2)

    ~H"""
    <article class="card h-100">
      <div class="card-body">
        <h3 class="card-title h6">{@sensor.name}</h3>
        <div class="d-flex align-items-center gap-3">
          <.co2_gauge :if={@co2? && @reading && @reading.co2} ppm={@reading.co2} />

          <div class="flex-grow-1">
            <%= if @reading do %>
              <ul class="list-unstyled mb-1">
                <li :if={@reading.temperature}>
                  <strong class="fs-5 tabular-nums">{de_number(@reading.temperature, precision: 1)}</strong>
                  °C
                </li>
                <li :if={@reading.humidity}>
                  <strong class="fs-5 tabular-nums">{@reading.humidity}</strong> % rH
                </li>
                <li :if={@co2? && @reading.co2}>
                  <strong class="fs-5 tabular-nums">{de_number(@reading.co2)}</strong> ppm
                </li>
              </ul>
              <div class="small text-body-secondary">
                {ReadingPresenter.age_label(@reading, @now)}
              </div>
            <% else %>
              <p class="small text-body-secondary mb-0">Keine Daten</p>
            <% end %>
          </div>
        </div>
      </div>
    </article>
    """
  end

  attr :sensors, :list, required: true

  def charts(assigns) do
    assigns =
      assign(assigns, :co2_sensors, Enum.filter(assigns.sensors, &(&1.type == :meter_pro_co2)))

    ~H"""
    <div data-controller="sensors-chart" data-sensors-chart-url-value="/sensors/series">
      <.card title="CO₂" subtitle={chart_subtitle("ppm", @co2_sensors)}>
        <div class="chart-frame chart-frame-prominent">
          <canvas data-sensors-chart-target="co2"></canvas>
        </div>
      </.card>

      <div class="row row-cols-1 row-cols-md-2 g-3">
        <div class="col">
          <.card title="Temperatur" subtitle={chart_subtitle("°C", @sensors)}>
            <div class="chart-frame chart-frame-compact">
              <canvas data-sensors-chart-target="temperature"></canvas>
            </div>
          </.card>
        </div>

        <div class="col">
          <.card title="Luftfeuchtigkeit" subtitle={chart_subtitle("Prozent", @sensors)}>
            <div class="chart-frame chart-frame-compact">
              <canvas data-sensors-chart-target="humidity"></canvas>
            </div>
          </.card>
        </div>
      </div>
    </div>
    """
  end

  # A chart of one sensor names it; several have a legend.
  defp chart_subtitle(unit, [sensor]), do: "#{unit} · #{sensor.name} · letzte 24 h"
  defp chart_subtitle(unit, _sensors), do: "#{unit} · letzte 24 h"

  @min_ppm 400
  @max_ppm 2000
  @center 60
  @radius 46
  @level_labels [good: "gut", warn: "erhöht", bad: "schlecht"]
  @felt_texture "https://felt-css.rocu.de/img/felt.svg"
  # Keeps felt-css's 256 px texture tile and 7 px stitch at the size the cards wear them.
  @texture_size 295
  @stitch_scale "1.15"
  @stitch_pitch 11

  @doc "A felt CO₂ gauge (`Sensors::Co2GaugeComponent`): three zones, the needle at `ppm`."
  attr :ppm, :integer, required: true

  def co2_gauge(assigns) do
    ppm = assigns.ppm
    level = ReadingPresenter.co2_level(%Reading{co2: ppm})
    # Each gauge on a page brings its own defs, so ids must not collide.
    uid = System.unique_integer([:positive])

    assigns =
      assign(assigns,
        id: &"co2-gauge-#{&1}-#{uid}",
        label: "CO₂ #{GermanNumber.format(ppm, unit: "ppm")}, #{@level_labels[level]}",
        zones: zones(level),
        stitches: stitches(),
        needle_angle: RubyNumeric.format_fixed(share(ppm) * 180, 1),
        texture_size: @texture_size,
        felt_texture: @felt_texture,
        center: @center,
        needle_end: @center - @radius + 8
      )

    ~H"""
    <svg class="co2-gauge" viewBox="0 0 120 70" role="img" aria-label={@label}>
      <defs>
        <pattern
          id={@id.("texture")}
          patternUnits="userSpaceOnUse"
          width={@texture_size}
          height={@texture_size}
        >
          <image href={@felt_texture} width={@texture_size} height={@texture_size} />
        </pattern>
        <pattern
          id={@id.("thread")}
          width="1.25"
          height="4"
          patternUnits="userSpaceOnUse"
          patternTransform="rotate(-58)"
        >
          <rect width="1.25" height="4" fill="#fafafa" /><rect width=".5" height="4" fill="#e6e6e6" />
        </pattern>
        <radialGradient id={@id.("hole")}>
          <stop offset="0" stop-opacity=".16" /><stop offset="1" stop-opacity="0" />
        </radialGradient>
        <g id={@id.("stitch")}>
          <circle cx="-3.2" r=".9" fill={"url(##{@id.("hole")})"} />
          <circle cx="3.2" r=".9" fill={"url(##{@id.("hole")})"} />
          <path
            d="M-3.5 0C-2.7 -.8 -1.9 -.8 -1.1 -.8H1.1C1.9 -.8 2.7 -.8 3.5 0C2.7 .8 1.9 .8 1.1 .8H-1.1C-1.9 .8 -2.7 .8 -3.5 0Z"
            fill={"url(##{@id.("thread")})"}
          />
          <rect x="-1.7" y="-.3" width="3.4" height=".34" rx=".17" fill="#fff" opacity=".7" />
        </g>
        <%!-- The region spans the whole drawing: a stroked arc's bounding box leaves out half its width. --%>
        <filter
          id={@id.("cut")}
          filterUnits="userSpaceOnUse"
          x="-5"
          y="-5"
          width="130"
          height="80"
          color-interpolation-filters="sRGB"
        >
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.9"
            numOctaves="2"
            seed="7"
            result="fibres"
          />
          <feDisplacementMap
            in="SourceGraphic"
            in2="fibres"
            scale="1.6"
            xChannelSelector="R"
            yChannelSelector="G"
          />
          <feDropShadow class="co2-gauge-shadow" dx="0" dy="1.2" stdDeviation="0.9" />
        </filter>
      </defs>
      <g class="co2-gauge-piece" filter={"url(##{@id.("cut")})"}>
        <%= for {level, path, current} <- @zones do %>
          <path class={["co2-gauge-zone", current && "is-current"]} data-level={level} d={path} />
          <path class="co2-gauge-texture" d={path} stroke={"url(##{@id.("texture")})"} />
        <% end %>
      </g>
      <g class="co2-gauge-stitches">
        <use :for={transform <- @stitches} href={"##{@id.("stitch")}"} transform={transform} />
      </g>
      <g class="co2-gauge-piece" filter={"url(##{@id.("cut")})"}>
        <g class="co2-gauge-needle" transform={"rotate(#{@needle_angle} #{@center} #{@center})"}>
          <line x1={@center} y1={@center} x2={@needle_end} y2={@center} />
        </g>
        <circle class="co2-gauge-hub" cx={@center} cy={@center} r="6" />
        <circle
          class="co2-gauge-texture"
          cx={@center}
          cy={@center}
          r="6"
          fill={"url(##{@id.("texture")})"}
        />
      </g>
      <g class="co2-gauge-stitches">
        <use
          href={"##{@id.("stitch")}"}
          transform={"translate(#{@center} #{@center}) rotate(45) scale(0.8)"}
        />
        <use
          href={"##{@id.("stitch")}"}
          transform={"translate(#{@center} #{@center}) rotate(-45) scale(0.8)"}
        />
      </g>
    </svg>
    """
  end

  defp zones(current) do
    bounds = [@min_ppm, ReadingPresenter.co2_warn_ppm(), ReadingPresenter.co2_bad_ppm(), @max_ppm]

    for {{level, _label}, [from, to]} <-
          Enum.zip(@level_labels, Enum.chunk_every(bounds, 2, 1, :discard)) do
      {level, "M #{point(share(from))} A #{@radius} #{@radius} 0 0 1 #{point(share(to))}",
       level == current}
    end
  end

  defp stitches do
    count = floor(:math.pi() * @radius / @stitch_pitch)

    for i <- 0..(count - 1) do
      at = (i + 0.5) / count

      "translate(#{point(at)}) rotate(#{RubyNumeric.format_fixed(at * 180 - 90, 1)}) scale(#{@stitch_scale})"
    end
  end

  defp point(at) do
    angle = :math.pi() * (1 - at)

    RubyNumeric.format_fixed(@center + @radius * :math.cos(angle), 1) <>
      " " <> RubyNumeric.format_fixed(@center - @radius * :math.sin(angle), 1)
  end

  defp share(ppm),
    do: ((ppm |> max(@min_ppm) |> min(@max_ppm)) - @min_ppm) / (@max_ppm - @min_ppm)
end
