defmodule ZiwoasWeb.Charts.Categories do
  @moduledoc """
  Categories on the chart series a chart leaves free (`ZiwoasWeb.Charts.Series`), by a rank
  that is the same on every page, so a category keeps its colour: consumer plugs by
  `Ziwoas.Plugs.consumer_rank/2`, sensors in config order. Categories beyond the free series
  share one "Weitere" series, as the hooks group the ids `tonesByOrder` leaves without a tone.
  """
  alias ZiwoasWeb.Charts.Series

  @other_label "Weitere"

  @type series :: pos_integer | :other

  @doc "The series of each id in `rank`, `:other` beyond the free ones."
  @spec series([term], [Series.semantic()]) :: %{term => series}
  def series(rank, semantic) do
    free = Series.free(semantic)
    rank |> Enum.with_index() |> Map.new(fn {id, index} -> {id, Enum.at(free, index, :other)} end)
  end

  @doc """
  Legend items for `{id, label}` pairs: one per plug on a free series, in rank order, then one
  "Weitere" for the plugs beyond.
  """
  @spec legend([{term, String.t()}], [term], [Series.semantic()]) :: [map]
  def legend(entries, rank, semantic) do
    series = series(rank, semantic)
    position = rank |> Enum.with_index() |> Map.new()

    {own, rest} =
      Enum.split_with(entries, fn {id, _label} -> Map.get(series, id, :other) != :other end)

    items =
      own
      |> Enum.sort_by(fn {id, _label} -> position[id] end)
      |> Enum.map(fn {id, label} -> %{label: label, color: series[id]} end)

    if rest == [], do: items, else: items ++ [%{label: @other_label, color: :other}]
  end
end
