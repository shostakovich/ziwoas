defmodule Ziwoas.Plugs.AggregatorJobTest do
  use Ziwoas.DataCase

  alias Ziwoas.Energy.DailySummary
  alias Ziwoas.Plugs.{AggregatorJob, DailyTotal}
  alias Ziwoas.{Repo, TestConfigs}
  alias Ziwoas.Solakon.{PvHour, Reading}

  setup do
    Ziwoas.TestClock.freeze("2026-04-11T08:00:00+02:00")
    :ok
  end

  defp perform, do: AggregatorJob.perform(config: TestConfigs.plugs(), backup_dir: nil)

  defp seed_day do
    start = berlin_midnight(~D[2026-04-10])
    insert_sample!("bkw", start, 10, 100)
    insert_sample!("bkw", start + 3600, 10, 150)
  end

  test "aggregates the finished days and tells Plugs' subscribers" do
    seed_day()
    Ziwoas.Plugs.subscribe(:aggregated)

    perform()

    assert_received {:aggregated, ~D[2026-04-11]}

    assert %DailyTotal{energy_wh: 50.0} =
             Repo.get_by!(DailyTotal, plug_id: "bkw", date: ~D[2026-04-10])

    assert Repo.get_by(DailySummary, date: ~D[2026-04-10])
  end

  test "condenses the inverter readings of finished days into PV hours" do
    from = ~U[2026-04-10 10:00:00.000000Z]

    for i <- 0..19 do
      Repo.insert!(%Reading{
        taken_at: DateTime.add(from, i * 30),
        pv_power_w: 300.0,
        active_power_w: 0.0,
        battery_power_w: 0.0,
        battery_soc_pct: 50
      })
    end

    perform()

    assert [%PvHour{started_at: ~U[2026-04-10 10:00:00.000000Z], pv_power_w: 300.0}] =
             Repo.all(PvHour)
  end
end
