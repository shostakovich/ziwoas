defmodule Ziwoas.PlugsTest do
  use Ziwoas.DataCase

  alias Ziwoas.Plugs
  alias Ziwoas.Plugs.{DailyTotal, Measurement, State}
  alias Ziwoas.Repo

  @now ~U[2026-10-05 10:00:00.500000Z]
  @now_s 1_791_194_400

  describe "latest_measurements" do
    test "the newest sample per plug, online within the offline window" do
      insert_sample!("bkw", @now_s - 200, 10, 1)
      insert_sample!("bkw", @now_s - 5, 300, 2)
      insert_sample!("fridge", @now_s - 121, 80, 1)

      assert Plugs.latest_measurements(["bkw", "fridge", "lamp"], @now) == %{
               "bkw" => %Measurement{
                 plug_id: "bkw",
                 watt: 300.0,
                 last_seen_ts: @now_s - 5,
                 offline: false
               },
               "fridge" => %Measurement{
                 plug_id: "fridge",
                 watt: 80.0,
                 last_seen_ts: @now_s - 121,
                 offline: true
               },
               "lamp" => %Measurement{
                 plug_id: "lamp",
                 watt: nil,
                 last_seen_ts: nil,
                 offline: true
               }
             }
    end

    test "the age keeps its fraction of a second against a custom window" do
      insert_sample!("fridge", @now_s - 10, 80, 1)

      assert %{"fridge" => %Measurement{offline: true}} =
               Plugs.latest_measurements(["fridge"], @now, 10)

      assert %{"fridge" => %Measurement{offline: false}} =
               Plugs.latest_measurements(["fridge"], @now, 10.5)
    end

    test "no plugs, no query" do
      assert Plugs.latest_measurements([], @now) == %{}
    end
  end

  describe "energy and power from raw samples" do
    test "energy_wh sums the plausible counter steps of the listed plugs in the window" do
      insert_sample!("fridge", 1_000, 0, 10.0)
      insert_sample!("fridge", 1_060, 0, 12.5)
      insert_sample!("tv", 1_000, 0, 1.0)
      insert_sample!("tv", 1_060, 0, 3.0)
      insert_sample!("fridge", 2_000, 0, 50.0)

      assert Plugs.energy_wh(["fridge"], 1_000, 2_000) == 2.5
      assert Plugs.energy_wh(["fridge", "tv"], 1_000, 2_000) == 4.5
      assert Plugs.energy_wh([], 1_000, 2_000) === 0.0
      assert Plugs.energy_wh(["lamp"], 1_000, 2_000) === 0.0
    end

    test "mean_power averages each plug per bucket, floored to the bucket width" do
      insert_sample!("fridge", 1_200, 100.0, 0)
      insert_sample!("fridge", 1_259, 200.0, 0)
      insert_sample!("fridge", 1_260, 50.0, 0)
      insert_sample!("tv", 1_230, 10.0, 0)
      insert_sample!("fridge", 1_320, 999.0, 0)

      assert Enum.sort(Plugs.mean_power(["fridge", "tv"], 1_200, 1_320, 60)) == [
               {"fridge", 1_200, 150.0},
               {"fridge", 1_260, 50.0},
               {"tv", 1_200, 10.0}
             ]

      assert Plugs.mean_power([], 0, 10_000, 60) == []
    end

    test "latest_sample_ts is the newest sample of the plugs in the window" do
      insert_sample!("fridge", 1_000, 0, 0)
      insert_sample!("tv", 1_500, 0, 0)
      insert_sample!("fridge", 3_000, 0, 0)

      assert Plugs.latest_sample_ts(["fridge", "tv"], 0, 2_000) == 1_500
      assert Plugs.latest_sample_ts(["fridge"], 2_000, 2_500) == nil
      assert Plugs.latest_sample_ts([], 0, 5_000) == nil
    end
  end

  describe "daily totals" do
    defp total!(plug_id, date, wh),
      do: Repo.insert!(%DailyTotal{plug_id: plug_id, date: date, energy_wh: wh})

    test "read back as dates, by date, for all plugs or the listed ones" do
      total!("tv", ~D[2026-04-02], 2.0)
      total!("fridge", ~D[2026-04-01], 1.0)
      total!("fridge", ~D[2026-04-03], 3.0)

      assert Plugs.daily_total_range() == Date.range(~D[2026-04-01], ~D[2026-04-03])
      assert Plugs.dates_with_daily_totals() == [~D[2026-04-01], ~D[2026-04-02], ~D[2026-04-03]]

      assert [~D[2026-04-01], ~D[2026-04-02]] ==
               Enum.map(Plugs.daily_totals(~D[2026-04-01], ~D[2026-04-02]), & &1.date)

      assert [%DailyTotal{plug_id: "tv"}] =
               Plugs.daily_totals(~D[2026-04-01], ~D[2026-04-30], ["tv"])
    end

    test "no range before the first total" do
      assert Plugs.daily_total_range() == nil
      assert Plugs.dates_with_daily_totals() == []
    end
  end

  test "record_output stores a relay output and says whether it changed" do
    assert Plugs.record_output("fridge", true)
    refute Plugs.record_output("fridge", true)
    assert Plugs.record_output("fridge", false)
    assert [%State{plug_id: "fridge", output: false}] = Repo.all(State)
    assert %{"fridge" => %State{output: false}} = Plugs.states(["fridge", "tv"])
    assert Plugs.states(["tv"]) == %{}
  end
end
