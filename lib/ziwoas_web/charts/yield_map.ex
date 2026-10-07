defmodule ZiwoasWeb.Charts.YieldMap do
  @moduledoc false
  import ZiwoasWeb.Format, only: [number: 2]

  alias Ziwoas.Shading
  alias ZiwoasWeb.Charts.{Plot, Ramp, Text}

  # Stretching the elevation keeps the fields close to square and the low morning sun readable.
  @frames [
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
  @width 720
  @left 52
  @right 10
  @top 16
  @bottom 36
  @axis_rounding_deg 10
  @azimuth_label_step 30
  @elevation_label_step 10
  @sparse_elevation_label_step 20
  @cell_gap 0.6
  @dot_label_offset 10
  @corner_label_offset 10
  @sideways 0.4
  @label_room 90
  @path_label_offset 9
  @elevation_label_gap 5
  @azimuth_label_gap 5
  @compass %{90 => "Ost", 180 => "Süd", 270 => "West"}
  @path_labels %{
    summer_solstice: "21.6.",
    equinox: "21.3. / 23.9.",
    winter_solstice: "21.12."
  }

  @spec gradient() :: String.t()
  def gradient, do: Ramp.css_gradient(Ramp.fetch(:diverging))

  @spec skies(Shading.SkyMap.t()) :: [map]
  def skies(%Shading.SkyMap{bins: []}), do: []
  def skies(%Shading.SkyMap{} = map), do: Enum.map(@frames, &sky(&1, map))

  defp sky(frame, map) do
    bin_size = map.bin_size
    degrees = fn pick -> Enum.flat_map(map.paths, fn path -> Enum.map(path.points, pick) end) end

    az_values =
      degrees.(&elem(&1, 0)) ++ Enum.flat_map(map.bins, &[&1.azimuth, &1.azimuth + bin_size])

    azimuths =
      {Plot.round_down(Enum.min(az_values), @axis_rounding_deg),
       Plot.round_up(Enum.max(az_values), @axis_rounding_deg)}

    top_elevation =
      Plot.round_up(
        Enum.max(degrees.(&elem(&1, 1)) ++ Enum.map(map.bins, &(&1.elevation + bin_size))),
        @axis_rounding_deg
      )

    {az_first, az_last} = azimuths
    scale_x = (@width - @left - @right) / :erlang.float(az_last - az_first)
    plot_height = top_elevation * scale_x * frame.stretch

    plot =
      Plot.new(
        width: @width,
        height: @top + plot_height + @bottom,
        margins: [top: @top, right: @right, bottom: @bottom, left: @left],
        x: azimuths,
        y: {0, top_elevation}
      )

    ramp = Ramp.fetch(:diverging)
    azimuth_label_y = Plot.number(Plot.y(plot, 0) + @azimuth_label_gap)

    %{
      key: frame.key,
      density: frame.density,
      plot: plot,
      dense_elevation_lines: elevation_lines(plot, top_elevation, :dense),
      elevation_lines: elevation_lines(plot, top_elevation, frame.density),
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
      paths: paths(map.paths, plot, frame)
    }
  end

  defp elevation_lines(plot, top_elevation, density) do
    step = if density == :sparse, do: @sparse_elevation_label_step, else: @elevation_label_step

    for elevation <- Enum.to_list(0..top_elevation//step) do
      at = Plot.number(Plot.y(plot, elevation))
      %{at: at, label_at: at, text: "#{elevation}°"}
    end
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
          "Ausbeute #{number(bin.share * 100, unit: "%")} · #{bin.hours} Stunden · #{bin.first_hour}–#{bin.last_hour} Uhr"
    }
  end

  defp azimuth_label(azimuth, :sparse), do: @compass[azimuth]

  defp azimuth_label(azimuth, _density),
    do: [@compass[azimuth], "#{azimuth}°"] |> Enum.reject(&is_nil/1) |> Enum.join(" ")

  defp paths(paths, plot, frame) do
    drawn = Enum.reject(paths, &(&1.points == []))
    peak_of = fn path -> path.points |> Enum.map(&elem(&1, 1)) |> Enum.max() end
    lowest = if length(drawn) > 1, do: Enum.min_by(drawn, peak_of)

    drawn
    |> Enum.with_index()
    |> Enum.map(fn {path, index} ->
      path(path, plot, frame, index == 0, lowest != nil and path === lowest)
    end)
  end

  defp path(path, plot, frame, hours, beneath) do
    {peak_az, peak_el} = Enum.max_by(path.points, &elem(&1, 1))
    offset = if beneath, do: @path_label_offset, else: -@path_label_offset

    %{
      label: Map.fetch!(@path_labels, path.day),
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
      text: if(hours and named?(frame, dot.hour), do: Text.hour(dot.hour, :clock))
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
    length = :math.sqrt(dx * dx + dy * dy)
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
end
