defmodule Ziwoas.Solakon.PvHourAggregatorTest do
  use Ziwoas.DataCase

  import Ecto.Query

  alias Ziwoas.Repo
  alias Ziwoas.Solakon.{PvHour, PvHourAggregator, Reading, Snapshot}

  @zone "Europe/Berlin"

  defp readings!(start, count, low, high) do
    for i <- 0..(count - 1) do
      Repo.insert!(%Reading{
        taken_at: start |> DateTime.add(i * 60) |> usec(),
        active_power_w: 0.0,
        pv_power_w: if(rem(i, 2) == 0, do: low, else: high),
        battery_power_w: 0.0,
        battery_soc_pct: 50
      })
    end
  end

  defp snapshot!(taken_at, panels) do
    [pv1, pv2, pv3, pv4] = panels

    Repo.insert!(%Snapshot{
      taken_at: usec(taken_at),
      pv1_power_w: pv1,
      pv2_power_w: pv2,
      pv3_power_w: pv3,
      pv4_power_w: pv4
    })
  end

  defp hours, do: Repo.all(from h in PvHour, order_by: h.started_at)

  test "an hour with enough readings becomes its mean, with the panels' means beside it" do
    readings!(~U[2026-06-20 08:00:00Z], 30, 100.0, 300.0)
    snapshot!(~U[2026-06-20 08:10:00Z], [100.0, 50.0, 0.0, 10.0])
    snapshot!(~U[2026-06-20 08:40:00Z], [200.0, 70.0, 0.0, 30.0])

    assert PvHourAggregator.aggregate_day(@zone, ~D[2026-06-20]) == :ok

    assert [hour] = hours()
    assert hour.started_at == usec(~U[2026-06-20 08:00:00Z])
    assert {hour.pv_power_w, hour.reading_count} == {200.0, 30}

    assert {hour.pv1_power_w, hour.pv2_power_w, hour.pv3_power_w, hour.pv4_power_w} ==
             {150.0, 60.0, 0.0, 20.0}
  end

  test "an hour with fewer than 20 readings is dropped" do
    readings!(~U[2026-06-20 08:00:00Z], PvHourAggregator.min_readings() - 1, 100.0, 100.0)
    readings!(~U[2026-06-20 09:00:00Z], PvHourAggregator.min_readings(), 100.0, 100.0)

    PvHourAggregator.aggregate_day(@zone, ~D[2026-06-20])

    assert [%PvHour{started_at: started_at, reading_count: 20}] = hours()
    assert started_at == usec(~U[2026-06-20 09:00:00Z])
  end

  test "an hour without snapshots has no panel means" do
    readings!(~U[2026-06-20 08:00:00Z], 20, 100.0, 100.0)

    PvHourAggregator.aggregate_day(@zone, ~D[2026-06-20])

    assert [%PvHour{pv1_power_w: nil, pv4_power_w: nil, pv_power_w: 100.0}] = hours()
  end

  test "hours follow the local clock across the spring clock change" do
    readings!(~U[2026-03-29 00:00:00Z], 20, 50.0, 50.0)
    readings!(~U[2026-03-29 08:00:00Z], 20, 400.0, 400.0)

    PvHourAggregator.aggregate_day(@zone, ~D[2026-03-29])

    assert Enum.map(hours(), & &1.started_at) ==
             [usec(~U[2026-03-29 00:00:00Z]), usec(~U[2026-03-29 08:00:00Z])]
  end

  test "hours fall on the local clock also where the offset is not a whole hour" do
    readings!(~U[2026-06-20 04:30:00Z], 20, 100.0, 100.0)

    PvHourAggregator.aggregate_day("Asia/Kolkata", ~D[2026-06-20])

    assert [%PvHour{started_at: started_at}] = hours()
    assert started_at == usec(~U[2026-06-20 04:30:00Z])
  end

  test "aggregating a day again replaces its hours" do
    readings!(~U[2026-06-20 08:00:00Z], 20, 100.0, 100.0)
    PvHourAggregator.aggregate_day(@zone, ~D[2026-06-20])
    readings!(~U[2026-06-20 08:20:00Z], 20, 400.0, 400.0)

    PvHourAggregator.aggregate_day(@zone, ~D[2026-06-20])

    assert [%PvHour{pv_power_w: 250.0, reading_count: 40}] = hours()
  end

  describe "run_once" do
    test "without readings there is nothing to do" do
      assert PvHourAggregator.run_once(@zone, ~D[2026-06-22]) == :ok
      assert hours() == []
    end

    test "fills every finished day since the first reading that has no hours yet" do
      readings!(~U[2026-06-19 08:00:00Z], 20, 100.0, 100.0)
      readings!(~U[2026-06-21 08:00:00Z], 20, 200.0, 200.0)
      readings!(~U[2026-06-22 08:00:00Z], 20, 300.0, 300.0)

      Repo.insert!(%PvHour{
        started_at: usec(~U[2026-06-21 09:00:00Z]),
        pv_power_w: 1.0,
        reading_count: 20
      })

      assert PvHourAggregator.run_once(@zone, ~D[2026-06-22]) == :ok

      assert Enum.map(hours(), &{&1.started_at, &1.pv_power_w}) == [
               {usec(~U[2026-06-19 08:00:00Z]), 100.0},
               {usec(~U[2026-06-21 09:00:00Z]), 1.0}
             ]
    end
  end
end
