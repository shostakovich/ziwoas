defmodule Ziwoas.Switching.EdgeCalculatorTest do
  # Plain rules, no database.
  use ExUnit.Case, async: true

  alias Ziwoas.Switching.{EdgeCalculator, Rule}

  @zone "Europe/Berlin"

  defp local(y, m, d, h, min),
    do: DateTime.new!(Date.new!(y, m, d), Time.new!(h, min, 0), @zone)

  defp rule(opts) do
    %Rule{
      id: opts[:id],
      plug_id: Keyword.get(opts, :plug_id, "lamp"),
      action: Keyword.get(opts, :action, :on),
      at_minute: Keyword.get(opts, :at_minute, 1080),
      days: Keyword.get(opts, :days, [1])
    }
  end

  # A Zeitfenster is two rules; a caller that wants one crossing midnight puts the
  # off rule on the following weekdays itself.
  defp window(opts \\ []) do
    days = Keyword.get(opts, :days, [1])
    plug = Keyword.get(opts, :plug_id, "lamp")

    [
      rule(plug_id: plug, action: :on, at_minute: Keyword.get(opts, :on_at, 1080), days: days),
      rule(
        plug_id: plug,
        action: :off,
        at_minute: Keyword.get(opts, :off_at, 1380),
        days: Keyword.get(opts, :off_days, days)
      )
    ]
  end

  defp between(rules, from, to), do: EdgeCalculator.edges_between(rules, from, to, @zone)
  defp next(rules, from, to), do: EdgeCalculator.next_edge_per_plug(rules, from, to, @zone)
  defp same?(a, b), do: DateTime.compare(a, b) == :eq

  test "fires on and off edges on configured weekdays" do
    edges = between(window(), local(2026, 6, 15, 0, 0), local(2026, 6, 16, 0, 0))

    assert Enum.map(edges, & &1.action) == [:on, :off]
    assert same?(hd(edges).at, local(2026, 6, 15, 18, 0))
    assert same?(List.last(edges).at, local(2026, 6, 15, 23, 0))
    assert hd(edges).plug_id == "lamp"
  end

  test "skips days not in the weekday list" do
    assert between(window(days: [2]), local(2026, 6, 15, 0, 0), local(2026, 6, 16, 0, 0)) == []
  end

  test "a single rule fires exactly one edge, carrying its id" do
    rules = [rule(id: 42, action: :off, at_minute: 1320, days: [1])]
    assert [edge] = between(rules, local(2026, 6, 15, 0, 0), local(2026, 6, 17, 0, 0))
    assert {edge.action, edge.rule_id} == {:off, 42}
    assert same?(edge.at, local(2026, 6, 15, 22, 0))
  end

  test "a window across midnight is two rules on different weekdays" do
    rules = window(on_at: 1320, off_at: 360, off_days: [2])
    edges = between(rules, local(2026, 6, 15, 0, 0), local(2026, 6, 17, 0, 0))

    assert same?(hd(edges).at, local(2026, 6, 15, 22, 0))
    assert same?(List.last(edges).at, local(2026, 6, 16, 6, 0))
  end

  test "interval is exclusive at from, inclusive at to" do
    on_time = local(2026, 6, 15, 18, 0)

    assert between(window(), on_time, local(2026, 6, 15, 18, 30)) == []
    assert [edge] = between(window(), local(2026, 6, 15, 17, 0), on_time)
    assert same?(edge.at, on_time)
  end

  test "empty or inverted interval returns no edges" do
    t = local(2026, 6, 15, 12, 0)
    assert between(window(), t, t) == []
    assert between(window(), t, DateTime.add(t, -3600)) == []
  end

  test "edges at the same instant order off before on" do
    rules = window(on_at: 1080, off_at: 1140) ++ window(on_at: 1140, off_at: 1200)
    edges = between(rules, local(2026, 6, 15, 17, 0), local(2026, 6, 15, 19, 0))
    assert Enum.map(edges, & &1.action) == [:on, :off, :on]
  end

  test "next_edge_per_plug collapses to the earliest edge per plug" do
    rules =
      window(plug_id: "lamp", on_at: 1080, off_at: 1140) ++
        window(plug_id: "fan", on_at: 1100, off_at: 1380)

    edges = next(rules, local(2026, 6, 15, 17, 0), local(2026, 6, 15, 20, 0))
    lamp = Enum.find(edges, &(&1.plug_id == "lamp"))
    fan = Enum.find(edges, &(&1.plug_id == "fan"))

    assert length(edges) == 2
    assert lamp.action == :on and same?(lamp.at, local(2026, 6, 15, 18, 0))
    assert fan.action == :on and same?(fan.at, local(2026, 6, 15, 18, 20))
  end

  test "on edge wins a same-timestamp tie in next_edge_per_plug" do
    rules = window(on_at: 360, off_at: 600) ++ window(on_at: 600, off_at: 840)
    assert [edge] = next(rules, local(2026, 6, 15, 9, 0), local(2026, 6, 15, 20, 0))
    assert edge.action == :on
    assert same?(edge.at, local(2026, 6, 15, 10, 0))
  end

  test "fall-back repetition fires the edge only once, on the first pass" do
    rules = [rule(action: :on, at_minute: 150, days: [7])]
    assert [edge] = between(rules, local(2026, 10, 25, 0, 0), local(2026, 10, 25, 12, 0))
    assert edge.at.utc_offset + edge.at.std_offset == 7200
  end

  test "spring-forward gap shifts the edge forward" do
    rules = window(on_at: 150, off_at: 240, days: [7])
    assert [first, _] = between(rules, local(2026, 3, 29, 0, 0), local(2026, 3, 29, 12, 0))
    assert {first.at.hour, first.at.minute} == {3, 30}
  end
end
