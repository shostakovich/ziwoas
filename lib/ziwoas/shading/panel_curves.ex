defmodule Ziwoas.Shading.PanelCurves do
  @moduledoc """
  The four panels beside each other over the day. A panel that is not yet
  wired reports zero all day long rather than going absent, so only days on
  which every panel delivered at least once are counted — otherwise the two
  younger panels would drag their own curve down through months they never
  saw.
  """
  alias Ziwoas.Shading
  alias Ziwoas.Shading.{Curve, Hour, Panels}

  @keys [:pv1, :pv2, :pv3, :pv4]

  @spec build([Hour.t()]) :: Panels.t()
  def build(hours) do
    days = countable(hours)

    %Panels{
      curves: Shading.trim(curves(Enum.flat_map(days, &elem(&1, 1)))),
      days: length(days),
      since: days |> Enum.map(&elem(&1, 0)) |> Enum.min(Date, fn -> nil end)
    }
  end

  defp countable(hours) do
    hours
    |> Enum.filter(
      &(length(&1.panels) == length(@keys) and not Enum.any?(&1.panels, fn p -> is_nil(p) end))
    )
    |> Shading.group_by(&Hour.date/1)
    |> Enum.filter(fn {_date, group} -> all_delivered?(group) end)
  end

  defp all_delivered?(hours) do
    Enum.all?(0..(length(@keys) - 1), fn index ->
      Enum.any?(hours, &(Enum.at(&1.panels, index) > 0))
    end)
  end

  defp curves(hours) do
    by_hour = hours |> Shading.group_by(& &1.time.hour) |> Enum.sort_by(&elem(&1, 0))

    for {key, index} <- Enum.with_index(@keys) do
      points =
        for {clock, group} <- by_hour do
          watts = Enum.map(group, &Enum.at(&1.panels, index))
          {clock, Enum.sum(watts) / length(watts)}
        end

      %Curve{key: key, points: points}
    end
  end
end
