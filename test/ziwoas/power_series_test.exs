defmodule Ziwoas.PowerSeriesTest do
  use ExUnit.Case, async: true

  alias Ziwoas.PowerSeries

  test "from_samples skips the query when no plugs are given" do
    Ziwoas.Repo.put_dynamic_repo(:no_such_repo)
    series = PowerSeries.from_samples([], 0, 86_400, 300)

    assert PowerSeries.buckets(series) == []
    assert PowerSeries.self_consumed_wh(series, 5.0, 5.0) === 0
  end
end
