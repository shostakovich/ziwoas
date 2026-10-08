defmodule ZiwoasWeb.Components.DailyProfiles do
  @moduledoc false
  use ZiwoasWeb, :html

  import ZiwoasWeb.Components.ChartParts

  alias ZiwoasWeb.Charts.{DailyProfiles, Plot, Text}

  attr :profiles, :list, required: true

  def daily_profiles(assigns) do
    assigns =
      assign(assigns, view: DailyProfiles.view(assigns.profiles), keys: DailyProfiles.keys())

    ~H"""
    <.card
      title="Tagesgang je Monat"
      subtitle={if @view, do: "Mittlere Leistung je Stunde in W"}
      data-chart="daily-profiles"
    >
      <%= if is_nil(@view) do %>
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
            :for={multiple <- @view.multiples}
            class={"multiple col mb-0#{if multiple.partial, do: " partial"}"}
            data-month={multiple.month}
          >
            <figcaption class={"small fw-semibold mb-1#{if multiple.partial, do: " text-body-secondary"}"}>
              {multiple.label}
              <span class="fw-normal text-body-secondary">
                {multiple.days} {Text.days(multiple.days)}
              </span>
            </figcaption>
            <svg
              viewBox={Plot.view_box(@view.plot)}
              role="img"
              aria-label={"Tagesgang #{multiple.label}"}
              {if multiple.partial, do: [class: "opacity-50"], else: []}
            >
              <g class="grid">
                <line
                  :for={at <- @view.grid_lines}
                  x1={Plot.left(@view.plot)}
                  x2={Plot.right(@view.plot)}
                  y1={at}
                  y2={at}
                />
              </g>
              <g class="value-labels" dominant-baseline="central">
                <.value_texts labels={@view.value_labels} />
              </g>
              <g
                :for={density <- [:dense, :sparse]}
                class={"hour-labels label-#{density}"}
                dominant-baseline="hanging"
              >
                <text
                  :for={label <- @view.hour_labels[density]}
                  x={label.x}
                  y={label.y}
                  text-anchor="middle"
                >
                  {label.text}
                </text>
              </g>
              <line
                class="axis"
                x1={Plot.left(@view.plot)}
                x2={Plot.right(@view.plot)}
                y1={Plot.bottom(@view.plot)}
                y2={Plot.bottom(@view.plot)}
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
end
