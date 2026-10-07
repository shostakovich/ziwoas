defmodule ZiwoasWeb.SunChartComponents do
  @moduledoc """
  The PV page's SVG charts, ported from `Solakon::SunCalendarComponent`,
  `Solakon::ShadingComponent` (yield map, daily profiles, panel curves) and
  their `ChartParts`. Every chart is drawn twice: a wide frame, and a narrow
  one for the phone, where the 720-unit drawing would shrink to a strip.
  Numbers print as Ruby prints them (`Ziwoas.RubyNumeric.to_s/1`).
  """
  use ZiwoasWeb, :html

  import Bitwise
  import ZiwoasWeb.CoreComponents

  alias Ziwoas.{GermanNumber, Plot, Ramp, RubyNumeric, Shading, SunCalendar}
  alias Ziwoas.Shading.{Curve, YieldMap}

  @months ~w[Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez]
  @weekdays ~w[So Mo Di Mi Do Fr Sa]
  @frame_classes %{wide: "d-none d-sm-block", narrow: "d-sm-none"}
  @legend_classes "legend list-unstyled d-flex flex-wrap align-items-center column-gap-3 row-gap-1 small text-body-secondary"

  defp n(value), do: RubyNumeric.to_s(value)
  defp frame_classes(frame), do: Map.fetch!(@frame_classes, frame)
  # A phone shows no SVG tooltips.
  defp tooltips?(frame), do: frame == :wide
  defp month_name(month), do: Enum.at(@months, month - 1)

  # --- Chart parts --------------------------------------------------------------

  attr :class, :string, required: true
  slot :inner_block, required: true

  defp legend_list(assigns) do
    ~H"""
    <ul class={[legend_classes(), @class]}>{render_slot(@inner_block)}</ul>
    """
  end

  defp legend_classes, do: @legend_classes

  slot :inner_block, required: true

  defp legend_item(assigns) do
    ~H"""
    <li class="legend-item d-inline-flex align-items-center gap-2">{render_slot(@inner_block)}</li>
    """
  end

  attr :hits, :list, required: true

  defp hit_areas(assigns) do
    ~H"""
    <g class="hits">
      <rect
        :for={hit <- @hits}
        x={n(hit.rect.x)}
        y={n(hit.rect.y)}
        width={n(hit.rect.width)}
        height={n(hit.rect.height)}
      >
        <title>{hit.title}</title>
      </rect>
    </g>
    """
  end

  attr :labels, :list, required: true

  defp value_texts(assigns) do
    ~H"""
    <text
      :for={label <- @labels}
      x={n(label.x)}
      y={n(label.y)}
      text-anchor="end"
      {if label.zero, do: [class: "zero"], else: []}
    >
      {label.text}
    </text>
    """
  end

  # --- Sonnenkalender -----------------------------------------------------------

  @width 720
  @left 56
  @right 4
  @top 30
  @bottom_pad 4
  @row_heights [wide: 8, narrow: 25]
  @bars_heights [wide: 100, narrow: 240]
  @densities %{wide: :dense, narrow: :sparse}
  @bars_bottom 34
  @strip_margins [top: @top, right: @right, bottom: @bottom_pad, left: @left]
  @bars_margins [top: @top, right: @right, bottom: @bars_bottom, left: @left]
  @dense_hour_step 3
  @max_bar_grid_lines 4
  @sparse_hour_step 6
  @month_line_rise 4
  @month_label_offset 2
  @month_label_lift 6
  @axis_label_gap 5
  @month_label_gap 5
  # At the phone's size an hour label in the top rows would touch the month labels.
  @hour_label_clear_rows 2

  attr :calendar, SunCalendar.Year, required: true

  def sun_calendar(assigns) do
    calendar = assigns.calendar

    assigns =
      if SunCalendar.Year.empty?(calendar),
        do: assign(assigns, empty: true),
        else: assign(assigns, empty: false, cal: calendar_view(calendar))

    ~H"""
    <%= if @empty do %>
      <section class="card card-body mb-3 empty-state">
        <h2 class="card-title">Noch kein Sonnenkalender</h2>
        <p>Der Kalender erscheint, sobald die ersten Stundenwerte der PV-Leistung vorliegen.</p>
      </section>
    <% else %>
      <div class="sun-charts sun-calendar">
        <.card :for={strip <- @cal.strips} title={strip.title} level={3} data-strip={strip.key}>
          <svg
            :for={{frame, plot} <- @cal.strip_plots}
            viewBox={Plot.view_box(plot)}
            role="img"
            aria-label={"#{strip.title} je Stunde über das Jahr #{@cal.year}"}
            class={"strip-chart-#{frame} #{frame_classes(frame)}"}
          >
            <g class="grid">
              <line
                :for={at <- @cal.month_lines.(plot)}
                x1={n(at)}
                x2={n(at)}
                y1={n(Plot.top(plot) - @cal.month_line_rise)}
                y2={n(Plot.bottom(plot))}
              />
            </g>
            <g class={"month-labels label-#{@cal.density.(frame)}"}>
              <text
                :for={label <- @cal.month_labels.(plot, @cal.density.(frame))}
                x={n(label.x)}
                y={n(label.y)}
              >
                {label.text}
              </text>
            </g>
            <g class={"hour-labels label-#{@cal.density.(frame)}"} dominant-baseline="central">
              <text
                :for={label <- @cal.hour_labels.(plot, @cal.density.(frame))}
                x={n(label.x)}
                y={n(label.y)}
                text-anchor="end"
              >
                {label.text}
              </text>
            </g>
            <%= if frame == :wide do %>
              <g class="cells" id={"sun-cells-#{strip.key}"} shape-rendering="crispEdges">
                <g
                  :for={{fill, rects} <- @cal.cells.(strip)}
                  {if fill, do: [style: "fill: #{fill}"], else: [class: "nodata"]}
                >
                  <rect
                    :for={cell <- rects}
                    x={n(cell.x)}
                    y={n(cell.y)}
                    width={n(cell.width)}
                    height={n(cell.height)}
                  />
                </g>
              </g>
            <% else %>
              <use class="cells" href={"#sun-cells-#{strip.key}"} transform={@cal.cells_transform} />
            <% end %>
            <%= if @cal.lines? do %>
              <%= if strip.key == @cal.first_strip_key do %>
                <g class="sun-lines" id={"sun-lines-#{frame}"}>
                  <%= for event <- [:rise, :set, :noon], points <- @cal.sun_segments.(plot, event) do %>
                    <polyline class="sun-halo" points={points} /><polyline
                      class={"sun #{event}"}
                      points={points}
                    />
                  <% end %>
                </g>
              <% else %>
                <use class="sun-lines" href={"#sun-lines-#{frame}"} />
              <% end %>
            <% end %>
            <line
              :if={@cal.seam && strip.key == :pv}
              class="seam"
              x1={n(@cal.seam_x.(plot))}
              x2={n(@cal.seam_x.(plot))}
              y1={n(Plot.top(plot))}
              y2={n(Plot.bottom(plot))}
            />
            <.hit_areas :if={tooltips?(frame)} hits={@cal.hits.(plot)} />
          </svg>
          <.legend_list class="mt-2 mb-0">
            <.legend_item>
              0<span
                class="legend-ramp"
                style={"background: #{Ramp.css_gradient(Ramp.fetch(strip.ramp))}"}
              ></span>{GermanNumber.format(strip.max, unit: strip.unit)}
            </.legend_item>
            <.legend_item><span class="legend-box nodata"></span>keine Daten</.legend_item>
            <.legend_item :if={@cal.seam && strip.key == :pv}>
              <span class="legend-line seam"></span>Wechsel der Quelle
            </.legend_item>
            <.legend_item :if={@cal.lines?}>
              <span class="legend-line"></span>Sonnenaufgang und Sonnenuntergang
            </.legend_item>
            <.legend_item :if={@cal.lines?}>
              <span class="legend-line noon"></span>Sonnenhöchststand
            </.legend_item>
          </.legend_list>
          <p :if={@cal.seam && strip.key == :pv} class="note small text-body-secondary mt-3 mb-0">
            {@cal.seam_note}
          </p>
        </.card>

        <.card title="PV-Energie je Tag" level={3} data-strip="energy">
          <svg
            :for={{frame, plot} <- @cal.bars_plots}
            viewBox={Plot.view_box(plot)}
            role="img"
            aria-label={"PV-Energie je Tag über das Jahr #{@cal.year}"}
            class={"energy-chart-#{frame} #{frame_classes(frame)}"}
          >
            <g class="grid">
              <line
                :for={at <- @cal.month_lines.(plot)}
                x1={n(at)}
                x2={n(at)}
                y1={n(Plot.top(plot))}
                y2={n(Plot.bottom(plot))}
              />
            </g>
            <g class="grid">
              <line
                :for={at <- Plot.grid_lines(plot, @cal.bar_values)}
                x1={n(Plot.left(plot))}
                x2={n(Plot.right(plot))}
                y1={n(at)}
                y2={n(at)}
              />
            </g>
            <g class="hour-labels" dominant-baseline="central">
              <.value_texts labels={Plot.value_labels(plot, @cal.bar_values, @cal.axis_label_gap)} />
            </g>
            <text class="unit" x={n(Plot.left(plot))} y={n(Plot.top(plot) - @cal.month_label_lift)}>
              kWh
            </text>
            <g class={"month-labels label-#{@cal.density.(frame)}"} dominant-baseline="hanging">
              <text
                :for={label <- @cal.month_labels.(plot, @cal.density.(frame))}
                x={n(label.x)}
                y={n(Plot.bottom(plot) + @cal.month_label_gap)}
              >
                {label.text}
              </text>
            </g>
            <g class="bars" shape-rendering="crispEdges">
              <path
                :for={area <- @cal.bar_areas.(plot)}
                d={area}
              />
            </g>
            <line
              class="axis"
              x1={n(Plot.left(plot))}
              x2={n(Plot.right(plot))}
              y1={n(Plot.bottom(plot))}
              y2={n(Plot.bottom(plot))}
            />
            <.hit_areas :if={tooltips?(frame)} hits={@cal.hits.(plot)} />
          </svg>
          <p class="small text-body-secondary mt-2 mb-0">Tage ohne Stundenwerte bleiben leer.</p>
        </.card>
      </div>
    <% end %>
    """
  end

  # Everything the calendar template asks for, computed once per render.
  defp calendar_view(calendar) do
    {first_hour, last_hour} = calendar.hours
    hours = Enum.to_list(first_hour..last_hour//1)
    doys = Enum.map(calendar.days, & &1.doy)
    day_axis = {List.first(doys), List.last(doys) + 1}
    bars_max = max(ceil(RubyNumeric.to_f(calendar.max_kwh)), 1)

    strip_plots =
      for {frame, row_height} <- @row_heights do
        {frame,
         Plot.new(
           width: @width,
           height: @top + length(hours) * row_height + @bottom_pad,
           margins: @strip_margins,
           x: day_axis,
           y: {last_hour + 1, first_hour}
         )}
      end

    bars_plots =
      for {frame, height} <- @bars_heights do
        {frame,
         Plot.new(
           width: @width,
           height: @top + height + @bars_bottom,
           margins: @bars_margins,
           x: day_axis,
           y: {0, bars_max}
         )}
      end

    wide_plot = Keyword.fetch!(strip_plots, :wide)
    titles = Enum.map(calendar.days, &day_title/1)
    month_doys = for month <- 1..12, do: first_doy(calendar.year, month)
    first_strip = hd(calendar.strips)
    scale = Keyword.fetch!(@row_heights, :narrow) / Keyword.fetch!(@row_heights, :wide)

    %{
      year: calendar.year,
      strips: calendar.strips,
      first_strip_key: first_strip.key,
      strip_plots: strip_plots,
      bars_plots: bars_plots,
      density: &Map.fetch!(@densities, &1),
      month_line_rise: @month_line_rise,
      month_label_lift: @month_label_lift,
      month_label_gap: @month_label_gap,
      axis_label_gap: @axis_label_gap,
      month_lines: fn plot -> plot |> Plot.x_ticks(month_doys) |> Enum.map(& &1.at) end,
      month_labels: fn plot, density ->
        months = if density == :sparse, do: Enum.to_list(1..12//2), else: Enum.to_list(1..12)

        for month <- months do
          %Plot.Label{
            x: Plot.number(Plot.x(plot, first_doy(calendar.year, month)) + @month_label_offset),
            y: Plot.top(plot) - @month_label_lift,
            text: month_name(month)
          }
        end
      end,
      hour_labels: fn plot, density ->
        {step, pattern} =
          if density == :sparse, do: {@sparse_hour_step, :hour}, else: {@dense_hour_step, :clock}

        for hour <- hours,
            rem(hour, step) == 0 and hour >= first_hour + @hour_label_clear_rows do
          %Plot.Label{
            x: Plot.left(plot) - @axis_label_gap,
            y: Plot.number(Plot.y(plot, hour)),
            text: hour_text(hour, pattern)
          }
        end
      end,
      cells: fn strip -> cells(strip, hours, doys, wide_plot) end,
      cells_transform:
        "matrix(1 0 0 #{RubyNumeric.format_g(scale)} 0 #{n(Plot.number(@top * (1 - scale)))})",
      lines?: not SunCalendar.Lines.empty?(calendar.lines),
      sun_segments: fn plot, key -> Plot.polylines(plot, Map.fetch!(calendar.lines, key)) end,
      seam: calendar.seam,
      seam_x: fn plot -> Plot.number(Plot.x(plot, Date.day_of_year(calendar.seam))) end,
      seam_note: seam_note(calendar.seam),
      hits: fn plot -> Plot.hits(plot, doys, titles) end,
      bar_values: Enum.to_list(0..(bars_max - 1)//ceil(bars_max / @max_bar_grid_lines)),
      bar_areas: fn plot -> bar_areas(plot, calendar.days) end
    }
  end

  defp hour_text(hour, :hour), do: String.pad_leading(Integer.to_string(hour), 2, "0")
  defp hour_text(hour, :clock), do: hour_text(hour, :hour) <> ":00"

  defp first_doy(year, month), do: Date.day_of_year(Date.new!(year, month, 1))

  # Unmeasured hours get cells too: the ramp's low end is translucent, so a
  # ground under the whole plot would tint every quiet hour.
  defp cells(strip, hours, doys, wide_plot) do
    ramp = Ramp.fetch(strip.ramp)

    hours
    |> Enum.flat_map(&row_runs(strip, ramp, &1, doys))
    |> Shading.group_by(& &1.fill)
    |> Enum.map(fn {fill, runs} ->
      {fill,
       Enum.map(runs, fn run ->
         Plot.rect(wide_plot, {run.first, run.last + 1}, {run.hour, run.hour + 1})
       end)}
    end)
  end

  defp row_runs(strip, ramp, hour, doys) do
    doys
    |> Enum.reduce([], fn doy, runs ->
      value = Map.get(strip.values, {doy, hour})
      fill = value && Ramp.color(ramp, Ramp.level(value / strip.max))

      case runs do
        [%{fill: ^fill} = run | rest] -> [%{run | last: doy} | rest]
        _ -> [%{first: doy, last: doy, fill: fill, hour: hour} | runs]
      end
    end)
    |> Enum.reverse()
  end

  # One outline per run of days: single bars a column wide shimmer as moiré.
  defp bar_areas(plot, days) do
    days
    |> Enum.reject(&is_nil(&1.pv_kwh))
    |> Enum.chunk_while(
      [],
      fn
        day, [] -> {:cont, [day]}
        day, [previous | _] = run when day.doy == previous.doy + 1 -> {:cont, [day | run]}
        day, run -> {:cont, Enum.reverse(run), [day]}
      end,
      fn
        [] -> {:cont, []}
        run -> {:cont, Enum.reverse(run), []}
      end
    )
    |> Enum.map(fn run ->
      steps =
        Enum.map_join(run, fn day ->
          "V#{n(Plot.number(Plot.y(plot, day.pv_kwh)))}H#{n(Plot.number(Plot.x(plot, day.doy + 1)))}"
        end)

      bottom = n(Plot.bottom(plot))
      "M#{n(Plot.number(Plot.x(plot, hd(run).doy)))} #{bottom}#{steps}V#{bottom}Z"
    end)
  end

  defp seam_note(nil), do: nil

  defp seam_note(seam) do
    "Bis #{day_month(Date.add(seam, -1))} aus der Energie der Erzeuger-Steckdose (AC), " <>
      "ab #{day_month(seam)} aus der PV-Leistung des Wechselrichters (DC). " <>
      "Die gestrichelte Linie markiert den Wechsel."
  end

  defp day_month(date), do: Calendar.strftime(date, "%d.%m.")

  defp day_title(day) do
    date =
      "#{Enum.at(@weekdays, rem(Date.day_of_week(day.date), 7))} #{Calendar.strftime(day.date, "%d.%m.%Y")}"

    if Enum.all?([day.pv_kwh, day.irradiance_kwh_per_m2, day.cloud_avg], &is_nil/1) do
      "#{date} · keine Daten"
    else
      Enum.join(
        [
          date,
          measure("PV-Energie", day.pv_kwh, "kWh", 2),
          measure("Einstrahlung", day.irradiance_kwh_per_m2, "kWh/m²", 2),
          measure("Bewölkung", day.cloud_avg, "%", 0, true)
        ],
        " · "
      )
    end
  end

  defp measure(label, value, unit, precision, mean \\ false)
  defp measure(label, nil, _unit, _precision, _mean), do: "#{label} keine Daten"

  defp measure(label, value, unit, precision, mean),
    do:
      "#{label} #{if mean, do: "Ø "}#{GermanNumber.format(value, precision: precision, unit: unit)}"

  # --- Shading ------------------------------------------------------------------

  attr :report, Shading.Report, required: true

  def shading(assigns) do
    ~H"""
    <%= if Shading.Report.empty?(@report) do %>
      <section class="card card-body mb-3 empty-state">
        <h2 class="card-title">Noch keine Ausbeute</h2>
        <p>Die Karte erscheint, sobald die ersten Stundenwerte der PV-Leistung vorliegen.</p>
      </section>
    <% else %>
      <div class="sun-charts shading">
        <.yield_map map={@report.map} />
        <.daily_profiles profiles={@report.profiles} />
        <.panel_curves panels={@report.panels} />
      </div>
    <% end %>
    """
  end

  # --- Yield map ----------------------------------------------------------------

  # Stretching the elevation keeps the fields close to square and the low morning sun readable.
  @sky_frames [
    %{
      key: :wide,
      stretch: 1.45,
      density: :dense,
      hours: nil,
      hour_place: :outside,
      apex_anchor: "middle"
    },
    %{
      key: :narrow,
      stretch: 2.1,
      density: :sparse,
      hours: [12],
      hour_place: :corner,
      apex_anchor: "start"
    }
  ]
  @sky_width 720
  # Room for the phone's larger axis labels.
  @sky_left 52
  @sky_right 10
  @sky_top 16
  @sky_bottom 36
  @axis_rounding_deg 10
  @azimuth_label_step 30
  @elevation_label_step 10
  @sparse_elevation_label_step 20
  @cell_gap 0.6
  @dot_radius 3
  # Outside the highest arc lies empty sky, clear of every field.
  @dot_label_offset 10
  # Clears the phone's dot ring (radius 7, stroke 3) and the arc falling away beneath.
  @corner_label_offset 10
  @sideways 0.4
  # Less room beside its dot and a sideways label would run into the axis labels.
  @label_room 90
  @path_label_offset 9
  @elevation_label_gap 5
  @azimuth_label_gap 5
  @compass %{90 => "Ost", 180 => "Süd", 270 => "West"}

  attr :map, Shading.SkyMap, required: true

  def yield_map(assigns) do
    assigns =
      assign(assigns,
        skies:
          if(assigns.map.bins == [], do: [], else: Enum.map(@sky_frames, &sky(&1, assigns.map))),
        gradient: Ramp.css_gradient(Ramp.fetch(:diverging)),
        note:
          "Ausbeute ist die PV-Leistung geteilt durch die Einstrahlung derselben Stunde, " <>
            "bezogen auf die beste je gemessene Stunde. Gezählt werden nur Stunden mit mindestens " <>
            "#{YieldMap.min_irradiance_w_per_m2()} W/m²; ein Feld von #{assigns.map.bin_size}° × #{assigns.map.bin_size}° " <>
            "zeigt den Median seiner Stunden und bleibt unter #{YieldMap.min_hours()} Stunden leer.",
        dot_radius: @dot_radius
      )

    ~H"""
    <.card title="Ausbeute nach Sonnenstand" data-chart="yield-map">
      <%= if @map.bins == [] do %>
        <p class="note small text-body-secondary mb-0">
          Die Karte füllt sich, sobald Stunden mit Einstrahlung und PV-Leistung zusammenkommen.
        </p>
      <% else %>
        <svg
          :for={sky <- @skies}
          viewBox={Plot.view_box(sky.plot)}
          role="img"
          aria-label="Ausbeute nach Sonnenstand, Azimut über Sonnenhöhe"
          class={"yield-map-#{sky.key} #{frame_classes(sky.key)}"}
        >
          <g class="grid">
            <line
              :for={line <- sky.dense_elevation_lines}
              x1={n(Plot.left(sky.plot))}
              x2={n(Plot.right(sky.plot))}
              y1={n(line.at)}
              y2={n(line.at)}
            />
          </g>
          <g class={"hour-labels label-#{sky.density}"} dominant-baseline="central">
            <text
              :for={line <- sky.elevation_lines}
              x={n(sky.elevation_label_x)}
              y={n(line.label_at)}
              text-anchor="end"
            >
              {line.text}
            </text>
          </g>
          <g class="grid">
            <line
              :for={line <- sky.azimuth_lines}
              x1={n(line.at)}
              x2={n(line.at)}
              y1={n(Plot.top(sky.plot))}
              y2={n(Plot.bottom(sky.plot))}
            />
          </g>
          <g class={"month-labels label-#{sky.density}"} dominant-baseline="hanging">
            <text
              :for={line <- sky.azimuth_lines}
              x={n(line.at)}
              y={n(line.label_at)}
              text-anchor="middle"
            >
              {line.text}
            </text>
          </g>
          <g class="fields">
            <g :for={{color, fields} <- sky.fills} style={"fill: #{color}"}>
              <%= for field <- fields do %>
                <%= if tooltips?(sky.key) do %>
                  <rect
                    x={n(field.rect.x)}
                    y={n(field.rect.y)}
                    width={n(field.rect.width)}
                    height={n(field.rect.height)}
                    rx="1"
                  >
                    <title>{field.title}</title>
                  </rect>
                <% else %>
                  <rect
                    x={n(field.rect.x)}
                    y={n(field.rect.y)}
                    width={n(field.rect.width)}
                    height={n(field.rect.height)}
                    rx="1"
                  />
                <% end %>
              <% end %>
            </g>
          </g>
          <g :for={path <- sky.paths}>
            <polyline class="sun" points={path.points} />
            <%= for dot <- path.dots do %>
              <circle class="dot" cx={n(dot.x)} cy={n(dot.y)} r={@dot_radius} /><text
                :if={dot.text}
                class="dot-label"
                x={n(dot.text_x)}
                y={n(dot.text_y)}
                text-anchor={dot.anchor}
                dominant-baseline={dot.baseline}
              >
                {dot.text}
              </text>
            <% end %>
            <text
              class="path-label"
              x={n(path.label_x)}
              y={n(path.label_y)}
              text-anchor={path.anchor}
              dominant-baseline={path.baseline}
            >
              {path.label}
            </text>
          </g>
        </svg>
        <.legend_list class="mt-2 mb-0">
          <.legend_item>
            Ausbeute 0 %<span class="legend-ramp" style={"background: #{@gradient}"}></span>100 %
          </.legend_item>
          <.legend_item>
            <span class="legend-line"></span>Sonnenbahn, Punkte alle drei Stunden
          </.legend_item>
        </.legend_list>
        <details class="solakon-details small text-body-secondary mt-3">
          <summary>Wie wird gerechnet?</summary>
          <p class="note mt-2 mb-0">{@note}</p>
        </details>
      <% end %>
    </.card>
    """
  end

  defp sky(frame, map) do
    bin_size = map.bin_size
    degrees = fn pick -> Enum.flat_map(map.paths, fn path -> Enum.map(path.points, pick) end) end

    az_values =
      degrees.(&elem(&1, 0)) ++ Enum.flat_map(map.bins, &[&1.azimuth, &1.azimuth + bin_size])

    azimuths =
      {Plot.round_down(RubyNumeric.min(az_values), @axis_rounding_deg),
       Plot.round_up(RubyNumeric.max(az_values), @axis_rounding_deg)}

    top_elevation =
      Plot.round_up(
        RubyNumeric.max(degrees.(&elem(&1, 1)) ++ Enum.map(map.bins, &(&1.elevation + bin_size))),
        @axis_rounding_deg
      )

    {az_first, az_last} = azimuths
    scale_x = (@sky_width - @sky_left - @sky_right) / :erlang.float(az_last - az_first)
    plot_height = top_elevation * scale_x * frame.stretch

    plot =
      Plot.new(
        width: @sky_width,
        height: @sky_top + plot_height + @sky_bottom,
        margins: [top: @sky_top, right: @sky_right, bottom: @sky_bottom, left: @sky_left],
        x: azimuths,
        y: {0, top_elevation}
      )

    elevation_lines = fn density ->
      step = if density == :sparse, do: @sparse_elevation_label_step, else: @elevation_label_step

      for elevation <- Enum.to_list(0..top_elevation//step) do
        at = Plot.number(Plot.y(plot, elevation))
        %{at: at, label_at: at, text: "#{elevation}°"}
      end
    end

    ramp = Ramp.fetch(:diverging)
    azimuth_label_y = Plot.number(Plot.y(plot, 0) + @azimuth_label_gap)

    %{
      key: frame.key,
      density: frame.density,
      plot: plot,
      dense_elevation_lines: elevation_lines.(:dense),
      elevation_lines: elevation_lines.(frame.density),
      elevation_label_x: Plot.left(plot) - @elevation_label_gap,
      azimuth_lines:
        for azimuth <-
              Enum.to_list(
                Plot.round_up(az_first, @azimuth_label_step)..az_last//@azimuth_label_step
              ),
            frame.density != :sparse or Map.has_key?(@compass, azimuth) do
          %{
            at: Plot.number(Plot.x(plot, azimuth)),
            label_at: azimuth_label_y,
            text: azimuth_label(azimuth, frame.density)
          }
        end,
      fills:
        map.bins
        |> Shading.group_by(&Ramp.color(ramp, Ramp.level(&1.share)))
        |> Enum.map(fn {color, bins} ->
          {color, Enum.map(bins, &field(&1, plot, bin_size))}
        end),
      paths: sky_paths(map.paths, plot, frame)
    }
  end

  defp field(bin, plot, bin_size) do
    %{
      rect:
        Plot.rect(
          plot,
          {bin.azimuth, bin.azimuth + bin_size},
          {bin.elevation, bin.elevation + bin_size},
          @cell_gap
        ),
      title:
        "Azimut #{bin.azimuth}–#{bin.azimuth + bin_size}° · Höhe #{bin.elevation}–#{bin.elevation + bin_size}° · " <>
          "Ausbeute #{GermanNumber.format(bin.share * 100, unit: "%")} · #{bin.hours} Stunden · #{bin.first_hour}–#{bin.last_hour} Uhr"
    }
  end

  defp azimuth_label(azimuth, :sparse), do: @compass[azimuth]

  defp azimuth_label(azimuth, _density),
    do: [@compass[azimuth], "#{azimuth}°"] |> Enum.reject(&is_nil/1) |> Enum.join(" ")

  defp sky_paths(paths, plot, frame) do
    drawn = Enum.reject(paths, &(&1.points == []))
    peak_of = fn path -> path.points |> Enum.map(&elem(&1, 1)) |> RubyNumeric.max() end
    lowest = if length(drawn) > 1, do: Enum.min_by(drawn, peak_of)

    drawn
    |> Enum.with_index()
    |> Enum.map(fn {path, index} ->
      path_view(path, plot, frame, index == 0, lowest != nil and path === lowest)
    end)
  end

  # The sun never stands under the lowest arc, so its date hangs there, clear of every field.
  defp path_view(path, plot, frame, hours, beneath) do
    peak = max_by_first(path.points, &elem(&1, 1))
    {peak_az, peak_el} = peak
    offset = if beneath, do: @path_label_offset, else: -@path_label_offset

    %{
      label: path.label,
      points: Plot.line(plot, path.points),
      dots: Enum.map(path.dots, &dot(&1, plot, frame, Plot.x(plot, peak_az), hours)),
      label_x: Plot.number(Plot.x(plot, peak_az)),
      label_y: Plot.number(Plot.y(plot, peak_el) + offset),
      anchor: if(beneath, do: "middle", else: frame.apex_anchor),
      baseline: if(beneath, do: "hanging", else: "auto")
    }
  end

  defp dot(dot, plot, frame, middle_x, hours) do
    at_x = Plot.x(plot, dot.azimuth)
    at_y = Plot.y(plot, dot.elevation)

    place =
      if frame.hour_place == :corner,
        do: corner(at_x, at_y, middle_x),
        else: outside(plot, at_x, at_y, middle_x)

    Map.merge(place, %{
      x: Plot.number(at_x),
      y: Plot.number(at_y),
      text: if(hours and named?(frame, dot.hour), do: hour_text(dot.hour, :clock))
    })
  end

  defp named?(%{hours: nil}, _hour), do: true
  defp named?(%{hours: hours}, hour), do: hour in hours

  defp outside(plot, at_x, at_y, middle_x) do
    {out_x, out_y} = room_for(plot, at_x, outwards(plot, at_x, at_y, middle_x))

    %{
      text_x: Plot.number(at_x + out_x * @dot_label_offset),
      text_y: Plot.number(at_y + out_y * @dot_label_offset),
      anchor: anchor(out_x),
      baseline: "central"
    }
  end

  defp corner(at_x, at_y, middle_x) do
    side = if at_x > middle_x, do: 1, else: -1

    %{
      text_x: Plot.number(at_x + side * @corner_label_offset),
      text_y: Plot.number(at_y - @corner_label_offset),
      anchor: if(side > 0, do: "start", else: "end"),
      baseline: "auto"
    }
  end

  defp outwards(plot, at_x, at_y, middle_x) do
    dx = at_x - middle_x
    dy = at_y - Plot.y(plot, 0)
    length = hypot(dx, dy)
    if length == 0, do: {0, -1}, else: {dx / length, dy / length}
  end

  defp room_for(plot, at_x, {out_x, out_y}) do
    room = if out_x < 0, do: at_x - Plot.left(plot), else: Plot.right(plot) - at_x

    if abs(out_x) < @sideways or room >= @label_room, do: {out_x, out_y}, else: {0, -1}
  end

  defp anchor(out_x) do
    cond do
      abs(out_x) < @sideways -> "middle"
      out_x < 0 -> "end"
      true -> "start"
    end
  end

  # Ruby's `max_by`: the first of equal maxima wins.
  defp max_by_first([first | rest], fun) do
    Enum.reduce(rest, first, fn item, best -> if fun.(item) > fun.(best), do: item, else: best end)
  end

  @doc false
  # C's hypot(3), taken as correctly rounded: the exact square root of the
  # exact sum of squares, rounded half to even. Erlang's :math has no hypot.
  def hypot(x, y) when x == 0, do: abs(:erlang.float(y))
  def hypot(x, y) when y == 0, do: abs(:erlang.float(x))

  def hypot(x, y) do
    {xn, xd} = RubyNumeric.exact(:erlang.float(x))
    {yn, yd} = RubyNumeric.exact(:erlang.float(y))
    # Both denominators are powers of two: scale to the larger one, 2^m.
    d = max(xd, yd)
    m = bit_length(d) - 1
    sum = Integer.pow(xn * div(d, xd), 2) + Integer.pow(yn * div(d, yd), 2)
    {keep, exponent} = sqrt_int(sum)
    keep * :math.pow(2, exponent - m)
  end

  # The square root of a positive integer as `{53-bit mantissa, binary exponent}`, rounded half to even.
  defp sqrt_int(n) do
    k = max(0, div(110 - bit_length(n), 2))
    scaled = n <<< (2 * k)
    r = isqrt(scaled)
    inexact = r * r != scaled
    s = bit_length(r) - 53
    keep = r >>> s
    rest = r &&& (1 <<< s) - 1
    half = 1 <<< (s - 1)

    keep =
      cond do
        rest > half -> keep + 1
        rest == half and (inexact or (keep &&& 1) == 1) -> keep + 1
        true -> keep
      end

    {keep, s - k}
  end

  defp isqrt(n) do
    x = 1 <<< div(bit_length(n) + 1, 2)
    isqrt_iter(n, x)
  end

  defp isqrt_iter(n, x) do
    y = div(x + div(n, x), 2)
    if y >= x, do: x, else: isqrt_iter(n, y)
  end

  defp bit_length(n), do: length(Integer.digits(n, 2))

  # --- Daily profiles -----------------------------------------------------------

  @dp_width 300
  @dp_height 160
  @dp_margins [top: 10, right: 14, bottom: 30, left: 48]
  @dp_nice_steps_w [100, 200, 250, 500, 1000]
  @dp_max_grid_steps 3
  @dp_value_label_gap 4
  @dp_hour_label_gap 8
  @dp_keys [
    measured: "PV gemessen",
    expected: "Erwartet aus Einstrahlung",
    theory: "Wolkenloser Himmel"
  ]

  attr :profiles, :list, required: true

  def daily_profiles(assigns) do
    profiles = assigns.profiles
    assigns = assign(assigns, empty: profiles == [], keys: @dp_keys)

    assigns =
      if profiles == [] do
        assigns
      else
        peak =
          profiles
          |> Enum.map(&Shading.max/1)
          |> Enum.reject(&is_nil/1)
          |> then(&if(&1 == [], do: 0.0, else: RubyNumeric.to_f(RubyNumeric.max(&1))))

        scale = Plot.nice_scale(peak, @dp_nice_steps_w, @dp_max_grid_steps)
        hours = Plot.extent(Enum.flat_map(profiles, &Shading.hours/1))

        plot =
          Plot.new(
            width: @dp_width,
            height: @dp_height,
            margins: @dp_margins,
            x: hours,
            y: {0, scale.top}
          )

        grid_values = Enum.to_list(0..scale.top//scale.step)

        assign(assigns,
          plot: plot,
          grid_lines: Plot.grid_lines(plot, grid_values),
          value_labels: Plot.value_labels(plot, grid_values, @dp_value_label_gap),
          hour_labels: %{
            dense: profile_hour_labels(plot, hours, 3),
            sparse: profile_hour_labels(plot, hours, 6)
          },
          multiples: Enum.map(profiles, &multiple(&1, plot))
        )
      end

    ~H"""
    <.card
      title="Tagesgang je Monat"
      subtitle={if !@empty, do: "Mittlere Leistung je Stunde in W"}
      data-chart="daily-profiles"
    >
      <%= if @empty do %>
        <p class="note small text-body-secondary mb-0">
          Der Tagesgang erscheint, sobald ein Monat Stundenwerte hat.
        </p>
      <% else %>
        <.legend_list class="mb-3">
          <.legend_item :for={{key, label} <- @keys}>
            <span class={"legend-line #{key}"}></span>{label}
          </.legend_item>
        </.legend_list>
        <div class="row row-cols-2 row-cols-lg-3 g-3">
          <figure
            :for={multiple <- @multiples}
            class={"multiple col mb-0#{if multiple.partial, do: " partial"}"}
            data-month={multiple.month}
          >
            <figcaption class={"small fw-semibold mb-1#{if multiple.partial, do: " text-body-secondary"}"}>
              {multiple.label}
              <span class="fw-normal text-body-secondary">
                {multiple.days} {if multiple.days == 1, do: "Tag", else: "Tage"}
              </span>
            </figcaption>
            <svg
              viewBox={Plot.view_box(@plot)}
              role="img"
              aria-label={"Tagesgang #{multiple.label}"}
              {if multiple.partial, do: [class: "opacity-50"], else: []}
            >
              <g class="grid">
                <line
                  :for={at <- @grid_lines}
                  x1={n(Plot.left(@plot))}
                  x2={n(Plot.right(@plot))}
                  y1={n(at)}
                  y2={n(at)}
                />
              </g>
              <g class="value-labels" dominant-baseline="central">
                <.value_texts labels={@value_labels} />
              </g>
              <g
                :for={density <- [:dense, :sparse]}
                class={"hour-labels label-#{density}"}
                dominant-baseline="hanging"
              >
                <text
                  :for={label <- @hour_labels[density]}
                  x={n(label.x)}
                  y={n(label.y)}
                  text-anchor="middle"
                >
                  {label.text}
                </text>
              </g>
              <line
                class="axis"
                x1={n(Plot.left(@plot))}
                x2={n(Plot.right(@plot))}
                y1={n(Plot.bottom(@plot))}
                y2={n(Plot.bottom(@plot))}
              />
              <polygon :for={area <- multiple.areas} class="measured-area" points={area} />
              <%= for {key, segments} <- multiple.series, points <- segments do %>
                <polyline class={"curve #{key}"} points={points} />
              <% end %>
              <.hit_areas hits={multiple.hits} />
            </svg>
          </figure>
        </div>
        <p class="note small text-body-secondary mt-3 mb-0">
          Einstrahlung und wolkenloser Himmel sind mit dem Wirkungsgrad der besten Stunde auf Anlagenleistung umgerechnet. Der Abstand zwischen der gemessenen und der erwarteten Linie ist der Anteil, den Abschattung, Ausrichtung oder Drosselung kosten.
        </p>
      <% end %>
    </.card>
    """
  end

  defp profile_hour_labels(plot, hours, step) do
    values = for hour <- Plot.domain_values(hours), rem(hour, step) == 0, do: hour

    for tick <- Plot.x_ticks(plot, values) do
      %Plot.Label{
        x: tick.at,
        y: Plot.bottom(plot) + @dp_hour_label_gap,
        text: hour_text(tick.value, :hour)
      }
    end
  end

  defp multiple(profile, plot) do
    values =
      Map.new(@dp_keys, fn {key, _label} ->
        {key, Map.new(Shading.curve(profile, key).points)}
      end)

    measured = profile |> Shading.hours() |> Enum.uniq() |> Enum.sort()

    %{
      month: profile.month,
      label: month_name(profile.month),
      days: profile.days,
      partial: profile.days < Date.days_in_month(Date.new!(2001, profile.month, 1)),
      # The measured line last, over the two it is read against.
      series:
        for(
          {key, _} <- Enum.reverse(@dp_keys),
          do: {key, Plot.polylines(plot, Shading.curve(profile, key).points)}
        ),
      areas: Plot.areas(plot, Shading.curve(profile, :measured).points),
      hits: Plot.hits(plot, measured, Enum.map(measured, &profile_title(profile, &1, values)))
    }
  end

  defp profile_title(profile, hour, values) do
    Enum.join(
      [
        "#{month_name(profile.month)} · #{hour}–#{hour + 1} Uhr"
        | for({key, label} <- @dp_keys, do: "#{label} #{watts(values[key][hour])}")
      ],
      " · "
    )
  end

  defp watts(nil), do: "keine Daten"
  defp watts(value), do: "Ø #{GermanNumber.format(value, unit: "W")}"

  # --- Panel curves -------------------------------------------------------------

  @panel_frames [
    %{
      key: :wide,
      width: 720,
      height: 220,
      hour_step: 2,
      named: true,
      margins: [top: 12, right: 88, bottom: 28, left: 40]
    },
    %{
      key: :narrow,
      width: 360,
      height: 240,
      hour_step: 3,
      named: false,
      margins: [top: 12, right: 12, bottom: 24, left: 36]
    }
  ]
  @panel_nice_steps_w [25, 50, 100, 200, 250, 500]
  @panel_max_steps 5
  # The names' line height at their largest, so two never overlap.
  @label_gap 20
  @label_offset 12
  @leader_gap 3
  # Half that line height: centred names stay clear of the hours.
  @label_margin 10
  @value_label_gap 5
  @unit_gap 3
  @hour_label_gap 5

  attr :panels, Shading.Panels, required: true

  def panel_curves(assigns) do
    panels = assigns.panels
    empty = Shading.Panels.empty?(panels)

    assigns =
      assign(assigns,
        empty: empty,
        charts: if(empty, do: [], else: panel_charts(panels)),
        legend: for(curve <- panels.curves, do: {curve.key, panel_name(curve.key)}),
        period: period(panels)
      )

    ~H"""
    <.card title="Die vier Panels im Tagesverlauf" subtitle={@period} data-chart="panels">
      <%= if @empty do %>
        <p class="note small text-body-secondary mb-0">
          Der Vergleich erscheint, sobald alle vier Panels einen Tag lang geliefert haben.
        </p>
      <% else %>
        <svg
          :for={chart <- @charts}
          viewBox={Plot.view_box(chart.plot)}
          role="img"
          aria-label="Stundenmittel je Panel über den Tag"
          class={"panel-chart panel-chart-#{chart.key} #{frame_classes(chart.key)}"}
        >
          <g class="grid">
            <line
              :for={at <- chart.grid_lines}
              x1={n(Plot.left(chart.plot))}
              x2={n(Plot.right(chart.plot))}
              y1={n(at)}
              y2={n(at)}
            />
          </g>
          <g class="value-labels" dominant-baseline="central">
            <.value_texts labels={chart.value_labels} />
            <text class="unit" x={n(chart.unit_label.x)} y={n(chart.unit_label.y)}>
              {chart.unit_label.text}
            </text>
          </g>
          <g class="hour-labels" dominant-baseline="hanging">
            <text
              :for={label <- chart.hour_labels}
              x={n(label.x)}
              y={n(label.y)}
              text-anchor="middle"
            >
              {label.text}
            </text>
          </g>
          <line
            class="axis"
            x1={n(Plot.left(chart.plot))}
            x2={n(Plot.right(chart.plot))}
            y1={n(Plot.bottom(chart.plot))}
            y2={n(Plot.bottom(chart.plot))}
          />
          <%= for {key, segments} <- chart.series, points <- segments do %>
            <polyline class={"curve #{key}"} points={points} />
          <% end %>
          <%= if chart.named do %>
            <g class="leaders">
              <line
                :for={label <- chart.labels}
                class={label.key}
                x1={n(label.line_x)}
                y1={n(label.line_y)}
                x2={n(label.x - leader_gap())}
                y2={n(label.y)}
              />
            </g>
            <g class="direct-labels" dominant-baseline="central">
              <text
                :for={label <- chart.labels}
                class={label.key}
                x={n(label.x)}
                y={n(label.y)}
              >
                {label.text}
              </text>
            </g>
          <% end %>
          <.hit_areas :if={tooltips?(chart.key)} hits={chart.hits} />
        </svg>
        <ul class="legend d-sm-none list-unstyled row row-cols-2 g-1 small text-body-secondary mt-2 mb-0">
          <li :for={{key, label} <- @legend} class="legend-item col d-flex align-items-center gap-2">
            <span class={"legend-line #{key}"}></span>{label}
          </li>
        </ul>
        <p class="note small text-body-secondary mt-3 mb-0">
          Gezählt sind nur Tage, an denen alle vier Panels geliefert haben — ein Panel, das noch nicht angeschlossen war, meldet null Watt und würde seine eigene Linie nach unten ziehen.
        </p>
      <% end %>
    </.card>
    """
  end

  defp leader_gap, do: @leader_gap

  defp period(%Shading.Panels{since: nil}), do: nil

  defp period(%Shading.Panels{since: since, days: days}),
    do:
      "seit #{Calendar.strftime(since, "%d.%m.%Y")} · #{days} #{if days == 1, do: "Tag", else: "Tage"}"

  defp panel_name(key), do: "Panel #{String.replace_prefix(Atom.to_string(key), "pv", "")}"

  defp panel_charts(panels) do
    curves = panels.curves
    hours = Plot.extent(Shading.hours(panels))
    scale = Plot.nice_scale(Shading.max(panels), @panel_nice_steps_w, @panel_max_steps)
    grid_values = Enum.to_list(0..scale.top//scale.step)
    hour_values = Plot.domain_values(hours)
    values = Map.new(curves, &{&1.key, Map.new(&1.points)})

    for frame <- @panel_frames do
      plot =
        Plot.new(
          width: frame.width,
          height: frame.height,
          margins: frame.margins,
          x: hours,
          y: {0, scale.top}
        )

      %{
        key: frame.key,
        named: frame.named,
        plot: plot,
        series: for(curve <- curves, do: {curve.key, Plot.polylines(plot, curve.points)}),
        labels: if(frame.named, do: end_labels(plot, curves), else: []),
        grid_lines: Plot.grid_lines(plot, grid_values),
        value_labels: Plot.value_labels(plot, grid_values, @value_label_gap),
        unit_label: %Plot.Label{
          x: Plot.left(plot) - @value_label_gap + @unit_gap,
          y: Plot.top(plot),
          text: "W"
        },
        hour_labels:
          for tick <-
                Plot.x_ticks(plot, Enum.filter(hour_values, &(rem(&1, frame.hour_step) == 0))) do
            %Plot.Label{
              x: tick.at,
              y: Plot.bottom(plot) + @hour_label_gap,
              text: hour_text(tick.value, if(frame.named, do: :clock, else: :hour))
            }
          end,
        hits:
          Plot.hits(plot, hour_values, Enum.map(hour_values, &panel_title(&1, curves, values)))
      }
    end
  end

  defp end_labels(plot, curves) do
    placed =
      curves
      |> Enum.reject(&Curve.empty?/1)
      |> Enum.map(&end_label(plot, &1))
      |> Enum.sort_by(& &1.y)
      |> spread()

    overflow =
      RubyNumeric.to_f(placed |> Enum.map(& &1.y) |> RubyNumeric.max()) -
        (Plot.bottom(plot) - @label_margin)

    if placed == [] or overflow <= 0,
      do: placed,
      else: Enum.map(placed, &%{&1 | y: Plot.number(&1.y - overflow)})
  end

  defp spread(labels) do
    labels
    |> Enum.reduce([], fn label, placed ->
      case placed do
        [previous | _] when label.y - previous.y < @label_gap ->
          [%{label | y: Plot.number(previous.y + @label_gap)} | placed]

        _ ->
          [label | placed]
      end
    end)
    |> Enum.reverse()
  end

  defp end_label(plot, curve) do
    {hour, watts} = max_by_first(curve.points, &elem(&1, 0))
    line_y = Plot.number(Plot.y(plot, watts))

    %{
      x: Plot.number(Plot.right(plot) + @label_offset),
      y: line_y,
      text: panel_name(curve.key),
      key: curve.key,
      line_x: Plot.number(Plot.x(plot, hour)),
      line_y: line_y
    }
  end

  defp panel_title(hour, curves, values) do
    Enum.join(
      [
        "#{hour}–#{hour + 1} Uhr"
        | for(curve <- curves, do: "#{panel_name(curve.key)} #{watts(values[curve.key][hour])}")
      ],
      " · "
    )
  end
end
