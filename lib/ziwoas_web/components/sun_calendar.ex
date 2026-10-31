defmodule ZiwoasWeb.Components.SunCalendar do
  @moduledoc "The narrow strips reuse the wide cells through `<use>`, so `id` prefixes the shared element ids."
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
    <section :if={@empty} id={"#{@id}-calendar"} aria-labelledby={"#{@id}-heading"}>
      <.section_heading id={"#{@id}-heading"}>Sonnenkalender</.section_heading>
      <.empty_state plush="sun" title="Noch kein Sonnenkalender">
        Der Kalender erscheint, sobald die ersten Stundenwerte der PV-Leistung vorliegen.
      </.empty_state>
    </section>
    <section
      :if={!@empty}
      id={"#{@id}-calendar"}
      class="sun-charts"
      aria-labelledby={"#{@id}-heading"}
    >
      <.section_heading id={"#{@id}-heading"}>Sonnenkalender {@cal.year}</.section_heading>
      <div class="flex flex-col gap-3 md:gap-6">
        <.chart_card
          :for={strip <- @cal.strips}
          id={"#{@id}-#{strip.key}"}
          title={strip.title}
          subtitle={"je Stunde in #{strip.unit}"}
          summary={"#{strip.title} je Stunde über das Jahr #{@cal.year}"}
          level={3}
          height={:auto}
          data-strip={strip.key}
        >
          <div class="sun-figure">
            <svg
              :for={frame <- @cal.strip_frames}
              viewBox={Plot.view_box(frame.plot)}
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
          </div>
          <:legend>
            <.keys class="mt-3">
              <.ramp_key
                gradient={strip.gradient}
                from="0"
                to={number(strip.max, unit: strip.unit)}
              />
              <.nodata_key />
              <.legend
                :if={line_keys(@cal, strip) != []}
                items={line_keys(@cal, strip)}
              />
            </.keys>
            <p
              :if={@cal.seam && strip.key == :pv}
              class="note text-xs text-base-content/70 max-w-prose mt-2"
            >
              {@cal.seam_note}
            </p>
          </:legend>
        </.chart_card>

        <.chart_card
          id={"#{@id}-energy"}
          title="PV-Energie je Tag"
          subtitle="in kWh"
          summary={"PV-Energie je Tag über das Jahr #{@cal.year}"}
          level={3}
          height={:auto}
          data-strip="energy"
        >
          <div class="sun-figure">
            <svg
              :for={frame <- @cal.bars_frames}
              viewBox={Plot.view_box(frame.plot)}
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
              <g class={"month-labels label-#{frame.density}"} dominant-baseline="hanging">
                <text :for={label <- frame.month_labels} x={label.x} y={label.y}>{label.text}</text>
              </g>
              <g class="bars fill-solar-fill stroke-solar" shape-rendering="crispEdges">
                <path :for={area <- frame.areas} d={area} vector-effect="non-scaling-stroke" />
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
          </div>
          <:legend>
            <p class="text-xs text-base-content/70 mt-3">Tage ohne Stundenwerte bleiben leer.</p>
          </:legend>
        </.chart_card>
      </div>
    </section>
    """
  end

  defp line_keys(cal, strip) do
    seam = cal.seam && strip.key == :pv

    [
      cal.lines? && %{label: "Sonnenaufgang und Sonnenuntergang", color: 2, marker: :line},
      cal.lines? && %{label: "Sonnenhöchststand", color: 2, marker: :dashed},
      seam && %{label: "Wechsel der Quelle", color: :neutral, marker: :dashed}
    ]
    |> Enum.filter(& &1)
  end
end
