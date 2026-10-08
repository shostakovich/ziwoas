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

    assigns =
      assign(assigns,
        empty: empty,
        charts: if(empty, do: [], else: PanelCurves.charts(panels)),
        legend: PanelCurves.legend(panels),
        period: PanelCurves.period(panels)
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
              x1={Plot.left(chart.plot)}
              x2={Plot.right(chart.plot)}
              y1={at}
              y2={at}
            />
          </g>
          <g class="value-labels" dominant-baseline="central">
            <.value_texts labels={chart.value_labels} />
            <text class="unit" x={chart.unit_label.x} y={chart.unit_label.y}>
              {chart.unit_label.text}
            </text>
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
            <polyline class={"curve #{key}"} points={points} />
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
              <text :for={label <- chart.labels} class={label.key} x={label.x} y={label.y}>
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
end
