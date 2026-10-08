defmodule ZiwoasWeb.Charts.SunCalendar do
  @moduledoc false
  import ZiwoasWeb.Format, only: [date: 1, day_month: 1, number: 2]

  alias Ziwoas.SunCalendar
  alias ZiwoasWeb.Charts.{Plot, Ramp, Text}

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
  @hour_label_clear_rows 2

  @strips %{
    pv: %{title: "PV-Leistung", unit: "W", ramp: :amber},
    irradiance: %{title: "Einstrahlung", unit: "W/m²", ramp: :blue},
    cloud: %{title: "Bewölkung", unit: "%", ramp: :grey}
  }

  @spec view(SunCalendar.Year.t()) :: map
  def view(%SunCalendar.Year{} = calendar) do
    {first_hour, last_hour} = calendar.hours
    hours = Enum.to_list(first_hour..last_hour//1)
    doys = Enum.map(calendar.days, & &1.doy)
    day_axis = {List.first(doys), List.last(doys) + 1}
    bars_max = max(ceil(calendar.max_kwh || 0), 1)
    bar_values = Enum.to_list(0..(bars_max - 1)//ceil(bars_max / @max_bar_grid_lines))
    month_doys = for month <- 1..12, do: first_doy(calendar.year, month)
    titles = Enum.map(calendar.days, &day_title/1)
    lines? = not SunCalendar.Lines.empty?(calendar.lines)
    scale = Keyword.fetch!(@row_heights, :narrow) / Keyword.fetch!(@row_heights, :wide)

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

    wide_plot = Keyword.fetch!(strip_plots, :wide)

    shared = %{
      year: calendar.year,
      hours: hours,
      first_hour: first_hour,
      doys: doys,
      titles: titles,
      month_doys: month_doys
    }

    %{
      year: calendar.year,
      strips: Enum.map(calendar.strips, &strip(&1, hours, doys, wide_plot)),
      first_strip_key: hd(calendar.strips).key,
      strip_frames:
        for({frame, plot} <- strip_plots, do: strip_frame(frame, plot, calendar, lines?, shared)),
      bars_frames:
        for {frame, height} <- @bars_heights do
          plot =
            Plot.new(
              width: @width,
              height: @top + height + @bars_bottom,
              margins: @bars_margins,
              x: day_axis,
              y: {0, bars_max}
            )

          bars_frame(frame, plot, calendar.days, bar_values, shared)
        end,
      cells_transform:
        "matrix(1 0 0 #{Float.round(scale * 1.0, 6)} 0 #{Plot.number(@top * (1 - scale))})",
      lines?: lines?,
      seam: calendar.seam,
      seam_note: seam_note(calendar.seam)
    }
  end

  defp strip(strip, hours, doys, wide_plot) do
    meta = Map.fetch!(@strips, strip.key)
    ramp = Ramp.fetch(meta.ramp)

    Map.merge(meta, %{
      key: strip.key,
      max: strip.max,
      gradient: Ramp.css_gradient(ramp),
      cells: cells(strip, ramp, hours, doys, wide_plot)
    })
  end

  defp strip_frame(frame, plot, calendar, lines?, shared) do
    density = Map.fetch!(@densities, frame)

    %{
      key: frame,
      density: density,
      plot: plot,
      month_lines: month_lines(plot, shared.month_doys, Plot.top(plot) - @month_line_rise),
      month_labels: month_labels(plot, density, shared.year, Plot.top(plot) - @month_label_lift),
      hour_labels: hour_labels(plot, density, shared.hours, shared.first_hour),
      sun_lines:
        if(lines?,
          do:
            for(
              event <- [:rise, :set, :noon],
              points <- Plot.polylines(plot, Map.fetch!(calendar.lines, event)),
              do: {event, points}
            ),
          else: []
        ),
      seam_x: calendar.seam && Plot.number(Plot.x(plot, Date.day_of_year(calendar.seam))),
      hits: hits(frame, plot, shared)
    }
  end

  defp bars_frame(frame, plot, days, bar_values, shared) do
    density = Map.fetch!(@densities, frame)

    %{
      key: frame,
      density: density,
      plot: plot,
      month_lines: month_lines(plot, shared.month_doys, Plot.top(plot)),
      grid_lines: Plot.grid_lines(plot, bar_values),
      value_labels: Plot.value_labels(plot, bar_values, @axis_label_gap),
      unit_label: %Plot.Label{
        x: Plot.left(plot),
        y: Plot.top(plot) - @month_label_lift,
        text: "kWh"
      },
      month_labels:
        month_labels(plot, density, shared.year, Plot.bottom(plot) + @month_label_gap),
      areas: bar_areas(plot, days),
      hits: hits(frame, plot, shared)
    }
  end

  defp hits(:wide, plot, shared), do: Plot.hits(plot, shared.doys, shared.titles)
  defp hits(_frame, _plot, _shared), do: []

  defp month_lines(plot, month_doys, from_y) do
    for tick <- Plot.x_ticks(plot, month_doys),
        do: %{x: tick.at, y1: from_y, y2: Plot.bottom(plot)}
  end

  defp month_labels(plot, density, year, y) do
    months = if density == :sparse, do: Enum.to_list(1..12//2), else: Enum.to_list(1..12)

    for month <- months do
      %Plot.Label{
        x: Plot.number(Plot.x(plot, first_doy(year, month)) + @month_label_offset),
        y: y,
        text: Text.month_name(month)
      }
    end
  end

  defp hour_labels(plot, density, hours, first_hour) do
    {step, pattern} =
      if density == :sparse, do: {@sparse_hour_step, :hour}, else: {@dense_hour_step, :clock}

    for hour <- hours,
        rem(hour, step) == 0 and hour >= first_hour + @hour_label_clear_rows do
      %Plot.Label{
        x: Plot.left(plot) - @axis_label_gap,
        y: Plot.number(Plot.y(plot, hour)),
        text: Text.hour(hour, pattern)
      }
    end
  end

  defp first_doy(year, month), do: Date.day_of_year(Date.new!(year, month, 1))

  # Unmeasured hours get cells too: under the translucent low end a full ground would tint them.
  defp cells(strip, ramp, hours, doys, wide_plot) do
    hours
    |> Enum.flat_map(&row_runs(strip, ramp, &1, doys))
    |> Ziwoas.Shading.group_by(& &1.fill)
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
          "V#{Plot.number(Plot.y(plot, day.pv_kwh))}H#{Plot.number(Plot.x(plot, day.doy + 1))}"
        end)

      bottom = Plot.bottom(plot)
      "M#{Plot.number(Plot.x(plot, hd(run).doy))} #{bottom}#{steps}V#{bottom}Z"
    end)
  end

  defp seam_note(nil), do: nil

  defp seam_note(seam) do
    "Bis #{day_month(Date.add(seam, -1))} aus der Energie der Erzeuger-Steckdose (AC), " <>
      "ab #{day_month(seam)} aus der PV-Leistung des Wechselrichters (DC). " <>
      "Die gestrichelte Linie markiert den Wechsel."
  end

  defp day_title(day) do
    date = "#{Text.weekday(day.date)} #{date(day.date)}"

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
    do: "#{label} #{if mean, do: "Ø "}#{number(value, precision: precision, unit: unit)}"
end
