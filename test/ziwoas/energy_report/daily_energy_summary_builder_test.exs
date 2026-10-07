defmodule Ziwoas.EnergyReport.DailyEnergySummaryBuilderTest do
  use Ziwoas.DataCase

  alias Ziwoas.EnergyReport.DailyEnergySummaryBuilder
  alias Ziwoas.Plugs.{Plug, Roster, Sample5min}
  alias Ziwoas.Repo

  @zone "Europe/Berlin"
  @plugs [
    %Plug{id: "bkw", name: "BKW", role: :producer},
    %Plug{id: "fridge", name: "Fridge", role: :consumer},
    %Plug{id: "tv", name: "TV", role: :consumer}
  ]

  defp bucket!(plug_id, ts, avg_power_w, energy_delta_wh) do
    Repo.insert!(%Sample5min{
      plug_id: plug_id,
      bucket_ts: ts,
      avg_power_w: avg_power_w * 1.0,
      energy_delta_wh: energy_delta_wh * 1.0,
      sample_count: 10
    })
  end

  defp midnight(date), do: berlin_midnight(date)

  test "a day without buckets is zero throughout" do
    assert DailyEnergySummaryBuilder.build(@plugs, @zone, ~D[2026-06-01]) == %{
             produced_wh: 0.0,
             consumed_wh: 0.0,
             self_consumed_wh: 0.0
           }
  end

  test "metered energy per role; self-consumption from the power overlap" do
    m = midnight(~D[2026-06-01])
    # Noon: the panel makes 1200 W while fridge and tv draw 300 W together.
    bucket!("bkw", m + 12 * 3600, -1200, 100)
    bucket!("fridge", m + 12 * 3600, 200, 20)
    bucket!("tv", m + 12 * 3600, 100, 5)
    # Evening: no sun.
    bucket!("fridge", m + 20 * 3600, 200, 17)

    summary = DailyEnergySummaryBuilder.build(@plugs, @zone, ~D[2026-06-01])

    assert summary.produced_wh == 100.0
    assert summary.consumed_wh == 42.0
    # 300 W for a twelfth of an hour.
    assert_in_delta summary.self_consumed_wh, 25.0, 1.0e-9
  end

  test "self-consumption never exceeds what the meters counted" do
    m = midnight(~D[2026-06-01])
    bucket!("bkw", m + 3600, -3000, 1)
    bucket!("fridge", m + 3600, 3000, 200)

    summary = DailyEnergySummaryBuilder.build(@plugs, @zone, ~D[2026-06-01])

    assert summary.self_consumed_wh == 1.0
  end

  test "buckets of plugs no longer configured count for nothing" do
    m = midnight(~D[2026-06-01])
    bucket!("old_heater", m + 3600, 2000, 500)
    bucket!("fridge", m + 3600, 100, 8)

    summary = DailyEnergySummaryBuilder.build(Roster.new(@plugs), @zone, ~D[2026-06-01])

    assert {summary.produced_wh, summary.consumed_wh} == {0.0, 8.0}
  end

  test "the local day runs from its midnight up to, not including, the next" do
    m = midnight(~D[2026-06-01])
    bucket!("fridge", m - 300, 100, 1)
    bucket!("fridge", m, 100, 2)
    bucket!("fridge", m + 86_400 - 300, 100, 4)
    bucket!("fridge", m + 86_400, 100, 8)

    assert DailyEnergySummaryBuilder.build(@plugs, @zone, ~D[2026-06-01]).consumed_wh == 6.0
  end

  test "a daylight-saving day has 23 or 25 hours of buckets" do
    for {date, hours} <- [{~D[2026-03-29], 23}, {~D[2026-10-25], 25}] do
      m = midnight(date)
      for hour <- 0..(hours - 1), do: bucket!("fridge", m + hour * 3600, 60, 1)
      bucket!("fridge", m + hours * 3600, 60, 1000)

      assert DailyEnergySummaryBuilder.build(@plugs, @zone, date).consumed_wh == hours * 1.0
    end
  end
end
