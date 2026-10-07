defmodule ZiwoasWeb.Charts.DailyProfiles do
  @moduledoc false
  alias Ziwoas.Shading
  alias ZiwoasWeb.Charts.{Plot, Text}

  @width 300
  @height 160
  @margins [top: 10, right: 14, bottom: 30, left: 48]
  @nice_steps_w [100, 200, 250, 500, 1000]
  @max_grid_steps 3
  @value_label_gap 4
  @hour_label_gap 8
  @keys [
    measured: "PV gemessen",
    expected: "Erwartet aus Einstrahlung",
    theory: "Wolkenloser Himmel"
  ]

  @spec keys() :: [{atom, String.t()}]
  def keys, do: @keys

  @spec view([Shading.Profile.t()]) :: map | nil
  def view([]), do: nil

  def view(profiles) do
    peak =
      profiles
      |> Enum.map(&Shading.max/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> 0.0 end)

    scale = Plot.nice_scale(peak, @nice_steps_w, @max_grid_steps)
    hours = Plot.extent(Enum.flat_map(profiles, &Shading.hours/1))

    plot =
      Plot.new(width: @width, height: @height, margins: @margins, x: hours, y: {0, scale.top})

    grid_values = Enum.to_list(0..scale.top//scale.step)

    %{
      plot: plot,
      grid_lines: Plot.grid_lines(plot, grid_values),
      value_labels: Plot.value_labels(plot, grid_values, @value_label_gap),
      hour_labels: %{dense: hour_labels(plot, hours, 3), sparse: hour_labels(plot, hours, 6)},
      multiples: Enum.map(profiles, &multiple(&1, plot))
    }
  end

  defp hour_labels(plot, hours, step) do
    values = for hour <- Plot.domain_values(hours), rem(hour, step) == 0, do: hour

    for tick <- Plot.x_ticks(plot, values) do
      %Plot.Label{
        x: tick.at,
        y: Plot.bottom(plot) + @hour_label_gap,
        text: Text.hour(tick.value, :hour)
      }
    end
  end

  defp multiple(profile, plot) do
    values =
      Map.new(@keys, fn {key, _label} -> {key, Map.new(Shading.curve(profile, key).points)} end)

    measured = profile |> Shading.hours() |> Enum.uniq() |> Enum.sort()

    %{
      month: profile.month,
      label: Text.month_name(profile.month),
      days: profile.days,
      partial: profile.days < Date.days_in_month(Date.new!(2001, profile.month, 1)),
      series:
        for(
          {key, _} <- Enum.reverse(@keys),
          do: {key, Plot.polylines(plot, Shading.curve(profile, key).points)}
        ),
      areas: Plot.areas(plot, Shading.curve(profile, :measured).points),
      hits: Plot.hits(plot, measured, Enum.map(measured, &title(profile, &1, values)))
    }
  end

  defp title(profile, hour, values) do
    Enum.join(
      [
        "#{Text.month_name(profile.month)} · #{hour}–#{hour + 1} Uhr"
        | for({key, label} <- @keys, do: "#{label} #{Text.mean_watts(values[key][hour])}")
      ],
      " · "
    )
  end
end
