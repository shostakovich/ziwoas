defmodule ZiwoasWeb.Components.YieldMap do
  @moduledoc false
  use ZiwoasWeb, :html

  import ZiwoasWeb.Components.ChartParts

  alias Ziwoas.Shading
  alias Ziwoas.Shading.YieldMap
  alias ZiwoasWeb.Charts.Plot

  @dot_radius 3

  attr :map, Shading.SkyMap, required: true

  def yield_map(assigns) do
    assigns =
      assign(assigns,
        skies: ZiwoasWeb.Charts.YieldMap.skies(assigns.map),
        gradient: ZiwoasWeb.Charts.YieldMap.gradient(),
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
              x1={Plot.left(sky.plot)}
              x2={Plot.right(sky.plot)}
              y1={line.at}
              y2={line.at}
            />
          </g>
          <g class={"hour-labels label-#{sky.density}"} dominant-baseline="central">
            <text
              :for={line <- sky.elevation_lines}
              x={sky.elevation_label_x}
              y={line.label_at}
              text-anchor="end"
            >
              {line.text}
            </text>
          </g>
          <g class="grid">
            <line
              :for={line <- sky.azimuth_lines}
              x1={line.at}
              x2={line.at}
              y1={Plot.top(sky.plot)}
              y2={Plot.bottom(sky.plot)}
            />
          </g>
          <g class={"month-labels label-#{sky.density}"} dominant-baseline="hanging">
            <text
              :for={line <- sky.azimuth_lines}
              x={line.at}
              y={line.label_at}
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
                    x={field.rect.x}
                    y={field.rect.y}
                    width={field.rect.width}
                    height={field.rect.height}
                    rx="1"
                  >
                    <title>{field.title}</title>
                  </rect>
                <% else %>
                  <rect
                    x={field.rect.x}
                    y={field.rect.y}
                    width={field.rect.width}
                    height={field.rect.height}
                    rx="1"
                  />
                <% end %>
              <% end %>
            </g>
          </g>
          <g :for={path <- sky.paths}>
            <polyline class="sun" points={path.points} />
            <%= for dot <- path.dots do %>
              <circle class="dot" cx={dot.x} cy={dot.y} r={@dot_radius} /><text
                :if={dot.text}
                class="dot-label"
                x={dot.text_x}
                y={dot.text_y}
                text-anchor={dot.anchor}
                dominant-baseline={dot.baseline}
              >
                {dot.text}
              </text>
            <% end %>
            <text
              class="path-label"
              x={path.label_x}
              y={path.label_y}
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
end
