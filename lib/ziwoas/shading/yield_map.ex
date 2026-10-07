defmodule Ziwoas.Shading.YieldMap do
  @moduledoc """
  The sky cut into fields of a few degrees: every hour lands where the sun
  stood, and a field keeps the median of its hours. The median, not the mean,
  because a single cloud passing through must not lift a field that lies in
  the shade every day.
  """
  alias Ziwoas.Shading
  alias Ziwoas.Shading.{Bin, Hour, SkyMap}

  @bin_size_deg 5
  @min_irradiance_w_per_m2 100
  @min_hours 3

  def min_irradiance_w_per_m2, do: @min_irradiance_w_per_m2
  def min_hours, do: @min_hours

  @spec build([Hour.t()], [Shading.Path.t()], float | nil) :: SkyMap.t()
  def build(hours, paths, best_ratio),
    do: %SkyMap{bins: bins(hours, best_ratio), paths: paths, bin_size: @bin_size_deg}

  defp bins(_hours, nil), do: []

  defp bins(hours, best_ratio) do
    for {{azimuth, elevation}, group} <- grouped(hours), length(group) >= @min_hours do
      clocks = Enum.map(group, & &1.time.hour)

      %Bin{
        azimuth: azimuth,
        elevation: elevation,
        share: median(Enum.map(group, &Hour.ratio/1)) / best_ratio,
        hours: length(group),
        first_hour: Enum.min(clocks),
        last_hour: Enum.max(clocks)
      }
    end
  end

  defp grouped(hours) do
    hours
    |> Enum.filter(&measured?/1)
    |> Shading.group_by(&{snap(&1.azimuth), snap(&1.elevation)})
  end

  defp measured?(hour) do
    not is_nil(Hour.ratio(hour)) and hour.irradiance_w_per_m2 >= @min_irradiance_w_per_m2 and
      Hour.positioned?(hour) and hour.elevation > 0
  end

  defp snap(degrees), do: floor(degrees / @bin_size_deg) * @bin_size_deg

  defp median(values) do
    sorted = Enum.sort(values)
    middle = div(length(sorted), 2)

    if rem(length(sorted), 2) == 1,
      do: Enum.at(sorted, middle),
      else: (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2.0
  end
end
