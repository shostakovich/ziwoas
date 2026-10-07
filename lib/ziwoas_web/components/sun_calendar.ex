defmodule ZiwoasWeb.Components.SunCalendar do
  @moduledoc """
  The sun calendar of the PV page: PV power, irradiance and cloud cover as
  strips of day × hour over a year, and the daily PV energy as bars. Every
  chart is drawn twice, wide and narrow for the phone; the narrow strips reuse
  the wide cells through `<use>`, so `id` prefixes the shared element ids.
  Geometry: `ZiwoasWeb.Charts.SunCalendar`.
  """
  use ZiwoasWeb, :html

  import ZiwoasWeb.Components.ChartParts

  alias Ziwoas.SunCalendar
  alias ZiwoasWeb.Charts.Plot

  attr :id, :string, default: "sun"
  attr :calendar, SunCalendar.Year, required: true

  def sun_calendar(assigns) do
    calendar = assigns.calendar

    assigns =
      if SunCalendar.Year.empty?(calendar),
        do: assign(assigns, empty: true),
        else: assign(assigns, empty: false, cal: ZiwoasWeb.Charts.SunCalendar.view(calendar))

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
            :for={frame <- @cal.strip_frames}
            viewBox={Plot.view_box(frame.plot)}
            role="img"
            aria-label={"#{strip.title} je Stunde über das Jahr #{@cal.year}"}
            class={"strip-chart-#{frame.key} #{frame_classes(frame.key)}"}
          >
            <g class="grid">
              <line
                :for={line <- frame.month_lines}
                x1={line.x}
                x2={line.x}
                y1={line.y1}
                y2={line.y2}
              />
            </g>
            <g class={"month-labels label-#{frame.density}"}>
              <text :for={label <- frame.month_labels} x={label.x} y={label.y}>{label.text}</text>
            </g>
            <g class={"hour-labels label-#{frame.density}"} dominant-baseline="central">
              <text :for={label <- frame.hour_labels} x={label.x} y={label.y} text-anchor="end">
                {label.text}
              </text>
            </g>
            <%= if frame.key == :wide do %>
              <g class="cells" id={"#{@id}-cells-#{strip.key}"} shape-rendering="crispEdges">
                <g
                  :for={{fill, rects} <- strip.cells}
                  {if fill, do: [style: "fill: #{fill}"], else: [class: "nodata"]}
                >
                  <rect
                    :for={cell <- rects}
                    x={cell.x}
                    y={cell.y}
                    width={cell.width}
                    height={cell.height}
                  />
                </g>
              </g>
            <% else %>
              <use
                class="cells"
                href={"##{@id}-cells-#{strip.key}"}
                transform={@cal.cells_transform}
              />
            <% end %>
            <%= if @cal.lines? do %>
              <%= if strip.key == @cal.first_strip_key do %>
                <g class="sun-lines" id={"#{@id}-lines-#{frame.key}"}>
                  <%= for {event, points} <- frame.sun_lines do %>
                    <polyline class="sun-halo" points={points} /><polyline
                      class={"sun #{event}"}
                      points={points}
                    />
                  <% end %>
                </g>
              <% else %>
                <use class="sun-lines" href={"##{@id}-lines-#{frame.key}"} />
              <% end %>
            <% end %>
            <line
              :if={@cal.seam && strip.key == :pv}
              class="seam"
              x1={frame.seam_x}
              x2={frame.seam_x}
              y1={Plot.top(frame.plot)}
              y2={Plot.bottom(frame.plot)}
            />
            <.hit_areas :if={tooltips?(frame.key)} hits={frame.hits} />
          </svg>
          <.legend_list class="mt-2 mb-0">
            <.legend_item>
              0<span class="legend-ramp" style={"background: #{strip.gradient}"}></span>{number(
                strip.max,
                unit: strip.unit
              )}
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
            :for={frame <- @cal.bars_frames}
            viewBox={Plot.view_box(frame.plot)}
            role="img"
            aria-label={"PV-Energie je Tag über das Jahr #{@cal.year}"}
            class={"energy-chart-#{frame.key} #{frame_classes(frame.key)}"}
          >
            <g class="grid">
              <line
                :for={line <- frame.month_lines}
                x1={line.x}
                x2={line.x}
                y1={line.y1}
                y2={line.y2}
              />
            </g>
            <g class="grid">
              <line
                :for={at <- frame.grid_lines}
                x1={Plot.left(frame.plot)}
                x2={Plot.right(frame.plot)}
                y1={at}
                y2={at}
              />
            </g>
            <g class="hour-labels" dominant-baseline="central">
              <.value_texts labels={frame.value_labels} />
            </g>
            <text class="unit" x={frame.unit_label.x} y={frame.unit_label.y}>
              {frame.unit_label.text}
            </text>
            <g class={"month-labels label-#{frame.density}"} dominant-baseline="hanging">
              <text :for={label <- frame.month_labels} x={label.x} y={label.y}>{label.text}</text>
            </g>
            <g class="bars" shape-rendering="crispEdges">
              <path :for={area <- frame.areas} d={area} />
            </g>
            <line
              class="axis"
              x1={Plot.left(frame.plot)}
              x2={Plot.right(frame.plot)}
              y1={Plot.bottom(frame.plot)}
              y2={Plot.bottom(frame.plot)}
            />
            <.hit_areas :if={tooltips?(frame.key)} hits={frame.hits} />
          </svg>
          <p class="small text-body-secondary mt-2 mb-0">Tage ohne Stundenwerte bleiben leer.</p>
        </.card>
      </div>
    <% end %>
    """
  end
end
