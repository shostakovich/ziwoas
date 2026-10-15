defmodule ZiwoasWeb.Components.PanelCurves do
  @moduledoc false
  use ZiwoasWeb, :html

  import ZiwoasWeb.Components.ChartParts

  alias Ziwoas.Shading
  alias ZiwoasWeb.Charts.{PanelCurves, Plot}

  attr :panels, Shading.Panels, required: true

  def panel_curves(assigns) do
    panels = assigns.panels
    empty = Shading.Panels.empty?(panels)

    legend = PanelCurves.legend(panels)

    assigns =
      assign(assigns,
        empty: empty,
        charts: if(empty, do: [], else: PanelCurves.charts(panels)),
        legend: Enum.map(legend, &%{label: &1.label, color: &1.color, marker: :line}),
        tones: Map.new(legend, &{&1.key, "--tone: #{&1.tone}"}),
        subtitle: join_meta(["Stundenmittel in W", PanelCurves.period(panels)])
      )

    ~H"""
    <.card :if={@empty} title="Die vier Panels im Tagesverlauf" level={3} data-chart="panels">
      <.empty_state>
        Der Vergleich erscheint, sobald alle vier Panels einen Tag lang geliefert haben.
      </.empty_state>
    </.card>
    <.chart_card
      :if={!@empty}
      id="panel-curves"
      title="Die vier Panels im Tagesverlauf"
      subtitle={@subtitle}
      summary="Stundenmittel je Panel über den Tag"
      level={3}
      height={:auto}
      data-chart="panels"
    >
      <div class="sun-figure">
        <svg
          :for={chart <- @charts}
          viewBox={Plot.view_box(chart.plot)}
          class={"panel-chart panel-chart-#{chart.key} #{frame_classes(chart.key)}"}
        >
          <g class="grid">
            <line
              :for={at <- chart.grid_lines}
              x1={Plot.left(chart.plot)}
              x2={Plot.right(chart.plot)}
              y1={at}
              y2={at}
            />
          </g>
          <g class="value-labels" dominant-baseline="central">
            <.value_texts labels={chart.value_labels} />
          </g>
          <g class="hour-labels" dominant-baseline="hanging">
            <text
              :for={label <- chart.hour_labels}
              x={label.x}
              y={label.y}
              text-anchor="middle"
            >
              {label.text}
            </text>
          </g>
          <line
            class="axis"
            x1={Plot.left(chart.plot)}
            x2={Plot.right(chart.plot)}
            y1={Plot.bottom(chart.plot)}
            y2={Plot.bottom(chart.plot)}
          />
          <%= for {key, segments} <- chart.series, points <- segments do %>
            <polyline class={"curve #{key}"} style={@tones[key]} points={points} />
          <% end %>
          <%= if chart.named do %>
            <g class="leaders">
              <line
                :for={label <- chart.labels}
                class={label.key}
                x1={label.line_x}
                y1={label.line_y}
                x2={label.leader_x}
                y2={label.y}
              />
            </g>
            <g class="direct-labels" dominant-baseline="central">
              <text
                :for={label <- chart.labels}
                class={label.key}
                style={@tones[label.key]}
                x={label.x}
                y={label.y}
              >
                {label.text}
              </text>
            </g>
          <% end %>
          <.hit_areas :if={tooltips?(chart.key)} hits={chart.hits} />
        </svg>
      </div>
      <:legend>
        <.legend items={@legend} class="mt-3 sm:hidden" />
        <p class="note text-xs text-base-content/70 max-w-prose mt-2">
          Gezählt sind nur Tage, an denen alle vier Panels geliefert haben. Ein Panel, das noch
          nicht angeschlossen war, meldet null Watt und würde seine eigene Linie nach unten ziehen.
        </p>
      </:legend>
    </.chart_card>
    """
  end
end
