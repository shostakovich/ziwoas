defmodule ZiwoasWeb.Charts.Series do
  @moduledoc """
  Setzkasten's eight chart series (`--color-chart-1` … `-8`) between a chart's semantic and
  categorical series, the same contract as `freeSeries`/`tonesByOrder` in
  `assets/js/lib/chart_theme.js`. A chart names the semantic series it shows; its categories
  take the series left free, in their stable order, never cycled. Categories beyond them get
  `other/0` and belong in one "Weitere" series.
  """

  @count 8
  @semantic %{grid: 1, consumption: 1, solar: 2, warning: 2, battery: 3, danger: 4}

  @type semantic :: :grid | :consumption | :solar | :warning | :battery | :danger

  @doc "The series a semantic one takes, e.g. for `<.bar color>`."
  @spec of(semantic) :: pos_integer
  def of(semantic), do: Map.fetch!(@semantic, semantic)

  @doc "The series numbers left for categories in a chart that shows `semantic`."
  @spec free([semantic]) :: [pos_integer]
  def free(semantic) do
    taken = Enum.map(semantic, &of/1)
    Enum.reject(1..@count, &(&1 in taken))
  end

  @doc "The colour of the category at the 0-based `position`, `other/0` beyond the free series."
  @spec color(non_neg_integer, [semantic]) :: String.t()
  def color(position, semantic) do
    case Enum.at(free(semantic), position) do
      nil -> other()
      series -> "var(--color-chart-#{series})"
    end
  end

  @doc "The colour of the grouped rest, \"Weitere\"."
  @spec other() :: String.t()
  def other, do: "var(--color-chart-other)"
end
