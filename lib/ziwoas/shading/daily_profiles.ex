defmodule Ziwoas.Shading.DailyProfiles do
  @moduledoc """
  The mean day of every month: measured PV against what the irradiance and a
  cloudless sky would have delivered, both scaled by the best hour's ratio.
  """
  alias Ziwoas.{RubyNumeric, Shading}
  alias Ziwoas.Shading.{ClearSky, Curve, Hour, Profile}

  @spec build([Hour.t()], float | nil) :: [Profile.t()]
  def build(hours, best_ratio) do
    hours
    |> Shading.group_by(& &1.time.month)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {month, group} ->
      basis = comparable(group)

      %Profile{
        month: month,
        days: basis |> Enum.map(&Hour.date/1) |> Enum.uniq() |> length(),
        curves: Shading.trim(curves(basis, best_ratio))
      }
    end)
  end

  defp comparable(hours) do
    case Enum.reject(hours, &is_nil(&1.irradiance_w_per_m2)) do
      [] -> hours
      measured -> measured
    end
  end

  defp curves(hours, best_ratio) do
    by_hour = hours |> Shading.group_by(& &1.time.hour) |> Enum.sort_by(&elem(&1, 0))

    [
      curve(:measured, by_hour, & &1.pv_w),
      curve(:expected, by_hour, &scaled(&1.irradiance_w_per_m2, best_ratio)),
      curve(:theory, by_hour, fn hour ->
        scaled(if(Hour.positioned?(hour), do: ClearSky.w_per_m2(hour.elevation)), best_ratio)
      end)
    ]
  end

  defp curve(key, by_hour, value) do
    points =
      for {clock, group} <- by_hour,
          values = group |> Enum.map(value) |> Enum.reject(&is_nil/1),
          values != [],
          do: {clock, RubyNumeric.sum(values) / length(values)}

    %Curve{key: key, points: points}
  end

  defp scaled(nil, _best_ratio), do: nil
  defp scaled(_w_per_m2, nil), do: nil
  defp scaled(w_per_m2, best_ratio), do: w_per_m2 * best_ratio
end
