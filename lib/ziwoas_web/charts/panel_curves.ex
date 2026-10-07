defmodule ZiwoasWeb.Charts.PanelCurves do
  @moduledoc false
  import ZiwoasWeb.Format, only: [date: 1]

  alias Ziwoas.Shading
  alias Ziwoas.Shading.Curve
  alias ZiwoasWeb.Charts.{Plot, Text}

  @frames [
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
  @nice_steps_w [25, 50, 100, 200, 250, 500]
  @max_steps 5
  @label_gap 20
  @label_offset 12
  @leader_gap 3
  @label_margin 10
  @value_label_gap 5
  @unit_gap 3
  @hour_label_gap 5

  @spec legend(Shading.Panels.t()) :: [{atom, String.t()}]
  def legend(panels), do: for(curve <- panels.curves, do: {curve.key, Text.panel_name(curve.key)})

  @spec period(Shading.Panels.t()) :: String.t() | nil
  def period(%Shading.Panels{since: nil}), do: nil

  def period(%Shading.Panels{since: since, days: days}),
    do: "seit #{date(since)} · #{days} #{Text.days(days)}"

  @spec charts(Shading.Panels.t()) :: [map]
  def charts(panels) do
    curves = panels.curves
    hours = Plot.extent(Shading.hours(panels))
    scale = Plot.nice_scale(Shading.max(panels), @nice_steps_w, @max_steps)
    grid_values = Enum.to_list(0..scale.top//scale.step)
    hour_values = Plot.domain_values(hours)
    values = Map.new(curves, &{&1.key, Map.new(&1.points)})

    for frame <- @frames do
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
              text: Text.hour(tick.value, if(frame.named, do: :clock, else: :hour))
            }
          end,
        hits: Plot.hits(plot, hour_values, Enum.map(hour_values, &title(&1, curves, values)))
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
      (placed |> Enum.map(& &1.y) |> Enum.max(fn -> 0.0 end)) -
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
    |> Enum.map(&%{&1 | leader_x: &1.x - @leader_gap})
  end

  defp end_label(plot, curve) do
    {hour, watts} = Enum.max_by(curve.points, &elem(&1, 0))
    line_y = Plot.number(Plot.y(plot, watts))

    %{
      x: Plot.number(Plot.right(plot) + @label_offset),
      y: line_y,
      leader_x: nil,
      text: Text.panel_name(curve.key),
      key: curve.key,
      line_x: Plot.number(Plot.x(plot, hour)),
      line_y: line_y
    }
  end

  defp title(hour, curves, values) do
    Enum.join(
      [
        "#{hour}–#{hour + 1} Uhr"
        | for(
            curve <- curves,
            do: "#{Text.panel_name(curve.key)} #{Text.mean_watts(values[curve.key][hour])}"
          )
      ],
      " · "
    )
  end
end
