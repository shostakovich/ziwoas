defmodule Ziwoas.Plugs.AggregatorTest do
  use Ziwoas.DataCase

  import Ecto.Query

  alias Ziwoas.Energy.DailySummary
  alias Ziwoas.Plugs.{Aggregator, DailyTotal, Plug, Sample, Sample5min}
  alias Ziwoas.Repo

  @zone "Europe/Berlin"
  @day ~D[2026-04-10]
  @plugs [
    %Plug{id: "bkw", name: "BKW", role: :producer},
    %Plug{id: "fridge", name: "Fridge", role: :consumer}
  ]

  defp seed do
    m = berlin_midnight(@day)
    # Two five-minute buckets of the fridge, one with a counter reset.
    insert_sample!("fridge", m, 100.0, 1000.0)
    insert_sample!("fridge", m + 60, 120.0, 1002.0)
    insert_sample!("fridge", m + 300, 80.0, 1003.0)
    insert_sample!("fridge", m + 360, 60.0, 0.5)
    insert_sample!("bkw", m + 300, -400.0, 50.0)
    insert_sample!("bkw", m + 360, -600.0, 60.0)
    # The next local day stays out.
    insert_sample!("fridge", m + 86_400, 100.0, 2000.0)
  end

  test "folds a day into five-minute means, daily totals and the energy summary" do
    seed()

    assert :ok = Aggregator.aggregate_day(@day, @zone, @plugs)

    m = berlin_midnight(@day)

    assert [
             %Sample5min{plug_id: "bkw", bucket_ts: b1, avg_power_w: -500.0, sample_count: 2},
             %Sample5min{plug_id: "fridge", bucket_ts: ^m, avg_power_w: 110.0, sample_count: 2},
             %Sample5min{plug_id: "fridge", bucket_ts: b1, avg_power_w: 70.0, sample_count: 2}
           ] = Repo.all(from s in Sample5min, order_by: [s.plug_id, s.bucket_ts])

    assert b1 == m + 300

    assert [
             %DailyTotal{plug_id: "bkw", date: @day, energy_wh: 10.0},
             %DailyTotal{plug_id: "fridge", date: @day, energy_wh: 3.0}
           ] = Repo.all(from d in DailyTotal, order_by: d.plug_id)

    assert %DailySummary{produced_wh: 10.0, consumed_wh: 3.0} = Repo.get!(DailySummary, @day)
  end

  test "running a day twice gives the same rows; without plugs no summary" do
    seed()

    Aggregator.aggregate_day(@day, @zone, nil)
    Aggregator.aggregate_day(@day, @zone, nil)

    assert Repo.aggregate(Sample5min, :count) == 3
    assert Repo.aggregate(DailyTotal, :count) == 2
    assert Repo.all(DailySummary) == []
  end

  test "run aggregates every finished day not yet totalled, then purges old samples" do
    seed()
    old = berlin_midnight(~D[2026-04-01])
    insert_sample!("fridge", old, 10.0, 1.0)

    :ok =
      Aggregator.run(@zone, @plugs, today: ~D[2026-04-11], now: berlin_midnight(~D[2026-04-11]))

    assert Ziwoas.Plugs.dates_with_daily_totals() == [~D[2026-04-01], @day]
    refute Repo.get_by(Sample, ts: old)
    assert Repo.get_by(Sample, plug_id: "fridge", ts: berlin_midnight(@day))
  end

  test "the purge keeps a sample exactly at the cutoff" do
    insert_sample!("fridge", 1_000, 1.0, 1.0)
    insert_sample!("fridge", 999, 1.0, 1.0)

    assert Aggregator.purge_old_raw(1_000 + 7 * 86_400) == 1
    assert [%Sample{ts: 1_000}] = Repo.all(Sample)
  end
end
