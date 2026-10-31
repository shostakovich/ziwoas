defmodule ZiwoasWeb.Charts.SeriesTest do
  use ExUnit.Case, async: true

  alias ZiwoasWeb.Charts.Series

  test "categories take the series a chart's semantic ones leave free, in order" do
    assert Series.free([]) == Enum.to_list(1..8)
    assert Series.free([:solar]) == [1, 3, 4, 5, 6, 7, 8]
    assert Series.free([:warning, :danger]) == [1, 3, 5, 6, 7, 8]
    assert Series.free([:grid, :consumption, :solar, :battery]) == [4, 5, 6, 7, 8]
  end

  test "a category's colour by position, the rest's beyond the free series, never cycled" do
    assert Series.color(0, [:solar]) == "var(--color-chart-1)"
    assert Series.color(1, [:solar]) == "var(--color-chart-3)"
    assert Series.color(6, [:solar]) == "var(--color-chart-8)"
    assert Series.color(7, [:solar]) == Series.other()
    assert Series.other() == "var(--color-chart-other)"
  end

  test "a semantic series' own number" do
    assert Series.of(:solar) == 2
    assert Series.of(:consumption) == 1
    assert Series.of(:battery) == 3
  end

  test "an unknown semantic series is an error, not a silent collision" do
    assert_raise KeyError, fn -> Series.free([:sun]) end
    assert_raise KeyError, fn -> Series.of(:sun) end
  end
end
