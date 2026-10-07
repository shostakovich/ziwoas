defmodule Ziwoas.Plugs.AggregatorTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Plugs.Aggregator

  test "the read-only repo refuses to aggregate" do
    aggregator = Aggregator.new(timezone: "Europe/Berlin")

    assert_raise Exqlite.Error, ~r/readonly database/, fn ->
      Aggregator.aggregate_day(aggregator, ~D[2026-04-10])
    end
  end
end
