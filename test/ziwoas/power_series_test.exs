defmodule Ziwoas.PowerSeriesTest do
  use ExUnit.Case, async: true

  alias Ziwoas.PowerSeries
  alias Ziwoas.Plugs.Plug

  @plugs [
    %Plug{id: "bkw", name: "BKW", role: :producer},
    %Plug{id: "fridge", name: "Fridge", role: :consumer},
    %Plug{id: "tv", name: "TV", role: :consumer}
  ]

  test "from_samples skips the query when no plugs are given" do
    Ziwoas.Repo.put_dynamic_repo(:no_such_repo)
    series = PowerSeries.from_samples([], 0, 86_400, 300)

    assert PowerSeries.buckets(series) == []
    assert PowerSeries.self_consumed_wh(series, 5.0, 5.0) === 0.0
  end

  test "buckets total each role, producers as a positive magnitude, oldest first" do
    series =
      PowerSeries.new(
        [{"fridge", 600, 50}, {"bkw", 300, -400.0}, {"tv", 300, 100.0}, {"fridge", 300, 80.0}],
        @plugs,
        300
      )

    assert [first, second] = PowerSeries.buckets(series)
    assert {first.ts, first.production_w, first.consumption_w} == {300, 400.0, 180.0}
    assert {second.ts, second.production_w, second.consumption_w} == {600, 0.0, 50.0}
    assert PowerSeries.signed_watts_by_ts(series, "bkw") == %{300 => 400.0}
    assert PowerSeries.signed_watts_by_ts(series, "unknown") == %{}
  end

  test "readings of plugs outside the roster and missing watts" do
    series = PowerSeries.new([{"other", 300, 999.0}, {"fridge", 300, nil}], @plugs, 300)

    assert [%{production_w: +0.0, consumption_w: +0.0}] = PowerSeries.buckets(series)
  end

  test "self-consumption is the per-bucket overlap, clamped to the meters" do
    # 5-minute buckets: 1/12 h each.
    series =
      PowerSeries.new(
        [{"bkw", 0, -1200.0}, {"fridge", 0, 600.0}, {"bkw", 300, -120.0}, {"fridge", 300, 600.0}],
        @plugs,
        300
      )

    # min(1200, 600) / 12 + min(120, 600) / 12 = 50 + 10
    assert_in_delta PowerSeries.self_consumed_wh(series, 1000.0, 1000.0), 60.0, 1.0e-9
    assert PowerSeries.self_consumed_wh(series, 1000.0, 30) === 30.0
    assert PowerSeries.self_consumed_wh(series, 20, 1000.0) === 20.0
  end

  test "bucket_ts_sql floors to the bucket width" do
    assert PowerSeries.bucket_ts_sql(300) == "(ts / 300) * 300"
  end
end
