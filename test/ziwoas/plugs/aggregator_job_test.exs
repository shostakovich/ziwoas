defmodule Ziwoas.Plugs.AggregatorJobTest do
  # test/jobs/aggregator_job_test.rb and Aggregator#backup! from test/aggregator_test.rb
  use Ziwoas.DataCase, async: true

  import Ecto.Query

  alias Ziwoas.{Ownership, Repo, TestConfigs}
  alias Ziwoas.EnergyReport.DailyEnergySummary
  alias Ziwoas.Plugs.{Aggregator, AggregatorJob, DailyTotal}
  alias Ziwoas.Solakon.{PvHour, Reading}

  @moduletag :tmp_dir

  setup %{repo: repo} do
    Repo.put_writer(:main, repo)
    Repo.put_writer(:shadow, repo)
    Ownership.override(%{aggregator: :phoenix})
    Ziwoas.Clock.freeze("2026-04-11T08:00:00+02:00")
    on_exit(&Ownership.clear_override/0)
    :ok
  end

  defp perform(dir),
    do:
      AggregatorJob.perform(%{
        task: :aggregator,
        mode: Ownership.mode(:aggregator),
        config: TestConfigs.plugs(),
        backup_dir: dir
      })

  defp seed_day do
    start = berlin_midnight(~D[2026-04-10])
    insert_sample!("bkw", start, 10, 100)
    insert_sample!("bkw", start + 3600, 10, 150)
  end

  defp backups(dir),
    do: dir |> Path.join("ziwoas-*.db") |> Path.wildcard() |> Enum.map(&Path.basename/1)

  test "aggregates the finished days and backs the database up", %{tmp_dir: dir} do
    seed_day()

    perform(dir)

    assert %DailyTotal{energy_wh: 50.0} =
             Repo.get_by!(DailyTotal, plug_id: "bkw", date: "2026-04-10")

    assert Repo.get_by(DailyEnergySummary, date: "2026-04-10")
    assert backups(dir) == ["ziwoas-2026-04-11.db"]
  end

  test "condenses the inverter readings of finished days into PV hours", %{tmp_dir: dir} do
    from = ~U[2026-04-10 10:00:00Z]

    for i <- 0..19 do
      Repo.insert!(%Reading{
        taken_at: DateTime.add(from, i * 30),
        pv_power_w: 300.0,
        active_power_w: 0.0,
        battery_power_w: 0.0,
        battery_soc_pct: 50
      })
    end

    perform(dir)

    assert [%PvHour{started_at: ~U[2026-04-10 10:00:00.000000Z], pv_power_w: 300.0}] =
             Repo.all(PvHour)
  end

  test "in shadow mode aggregates but leaves the backups to Rails", %{tmp_dir: dir} do
    Ownership.override(%{aggregator: :shadow})
    seed_day()

    perform(dir)

    assert Repo.exists?(from d in DailyTotal, where: d.date == "2026-04-10")
    assert backups(dir) == []
  end

  describe "backup!" do
    test "replaces the day's file and keeps the newest seven", %{tmp_dir: dir} do
      for day <- 1..9 do
        path = Path.join(dir, "ziwoas-2026-04-0#{day}.db")
        File.write!(path, "old")
        File.touch!(path, 1_775_000_000 + day * 86_400)
      end

      File.touch!(Path.join(dir, "ziwoas-2026-04-01.db"), 1_775_000_000 + 20 * 86_400)

      Aggregator.backup!(dir, ~D[2026-04-05])

      assert backups(dir) == Enum.map([1, 4, 5, 6, 7, 8, 9], &"ziwoas-2026-04-0#{&1}.db")
      assert File.read!(Path.join(dir, "ziwoas-2026-04-05.db")) =~ "SQLite format 3"
    end

    test "is the owner's only", %{tmp_dir: dir} do
      Ownership.override(%{aggregator: :shadow})

      assert_raise Ownership.NotOwnerError, fn -> Aggregator.backup!(dir, ~D[2026-04-05]) end
      assert File.ls!(dir) == []
    end
  end
end
