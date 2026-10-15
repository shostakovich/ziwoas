defmodule ZiwoasWeb.Components.DailyProfiles do
  @moduledoc false
  use ZiwoasWeb, :html

  import ZiwoasWeb.Components.ChartParts

  alias ZiwoasWeb.Charts.{DailyProfiles, Plot, Text}

  attr :profiles, :list, required: true

  def daily_profiles(assigns) do
    assigns =
      assign(assigns, view: DailyProfiles.view(assigns.profiles), keys: legend_items())

    ~H"""
    <.card :if={is_nil(@view)} title="Tagesgang je Monat" level={3} data-chart="daily-profiles">
      <.empty_state>Der Tagesgang erscheint, sobald ein Monat Stundenwerte hat.</.empty_state>
    </.card>
    <.chart_card
      :if={@view}
      id="daily-profiles"
      title="Tagesgang je Monat"
      subtitle="Mittlere Leistung je Stunde in W"
      summary="PV-Leistung je Stunde für jeden Monat: gemessen, aus der Einstrahlung erwartet und bei wolkenlosem Himmel"
      level={3}
      height={:auto}
      data-chart="daily-profiles"
    >
      <div class="grid grid-cols-2 lg:grid-cols-3 gap-x-4 gap-y-5">
        <figure
          :for={multiple <- @view.multiples}
          class={["multiple", multiple.partial && "partial"]}
          data-month={multiple.month}
        >
          <figcaption class="flex gap-1.5 text-sm mb-1">
            <span class={["font-semibold", multiple.partial && "text-base-content/70"]}>
              {multiple.label}
            </span>
            <span class="text-base-content/70 tabular-nums">
              {multiple.days} {Text.days(multiple.days)}
            </span>
          </figcaption>
          <div class="sun-figure">
            <svg viewBox={Plot.view_box(@view.plot)}>
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
          </div>
        </figure>
      </div>
      <:legend>
        <.legend items={@keys} class="mt-4" />
        <div class="flex flex-col gap-1 text-xs text-base-content/70 max-w-prose mt-2">
          <p class="sm:hidden" data-role="grid-step">
            Gitterlinien alle {number(@view.grid_step, unit: "W")}.
          </p>
          <p class="note">
            Einstrahlung und wolkenloser Himmel sind mit dem Verhältnis von PV-Leistung zu
            Einstrahlung der besten Stunde auf Anlagenleistung umgerechnet. Der Abstand zwischen der gemessenen und der erwarteten
            Linie ist der Anteil, den Abschattung, Ausrichtung oder Drosselung kosten.
          </p>
        </div>
      </:legend>
    </.chart_card>
    """
  end

  @markers %{
    measured: %{color: 2, marker: :line},
    expected: %{color: 1, marker: :dashed},
    theory: %{color: :neutral, marker: :line}
  }

  defp legend_items do
    for {key, label} <- DailyProfiles.keys(), do: Map.put(@markers[key], :label, label)
  end
end
