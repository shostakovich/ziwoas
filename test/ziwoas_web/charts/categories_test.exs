defmodule ZiwoasWeb.Charts.CategoriesTest do
  use ExUnit.Case, async: true

  alias ZiwoasWeb.Charts.Categories

  test "plugs take the free series in rank order, those beyond are :other" do
    rank = for i <- 1..9, do: "p#{i}"

    assert Categories.series(rank, [:solar]) == %{
             "p1" => 1,
             "p2" => 3,
             "p3" => 4,
             "p4" => 5,
             "p5" => 6,
             "p6" => 7,
             "p7" => 8,
             "p8" => :other,
             "p9" => :other
           }

    assert Categories.series(~w[b a], []) == %{"b" => 1, "a" => 2}
  end

  test "the legend lists its plugs in rank order and groups the rest once" do
    rank = ~w[c a b]

    assert Categories.legend([{"a", "A"}, {"c", "C"}], rank, [:solar]) == [
             %{label: "C", color: 1},
             %{label: "A", color: 3}
           ]

    rank = for i <- 1..9, do: "p#{i}"
    entries = for i <- [9, 7, 8], do: {"p#{i}", "P#{i}"}

    assert Categories.legend(entries, rank, [:solar]) == [
             %{label: "P7", color: 8},
             %{label: "Weitere", color: :other}
           ]
  end
end
