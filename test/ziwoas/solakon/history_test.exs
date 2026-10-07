defmodule Ziwoas.Solakon.HistoryTest do
  # Mirrors test/models/solakon/history_test.rb.
  use Ziwoas.DataCase

  alias Ziwoas.Repo
  alias Ziwoas.Solakon.{History, Reading, Snapshot}

  # 2026-06-20 12:00 Europe/Berlin
  @now ~U[2026-06-20 10:00:00.000000Z]

  defp snapshot!(seconds_ago, attrs) do
    floats =
      Map.new(attrs, fn
        {key, value} when is_integer(value) -> {key, value * 1.0}
        pair -> pair
      end)

    Repo.insert!(struct!(%Snapshot{taken_at: DateTime.add(@now, -seconds_ago)}, floats))
  end

  defp payload(range \\ "24h"), do: History.payload(range, @now, "Europe/Berlin")
  defp shares(payload), do: Enum.map(payload.balance_rows, & &1.share)
  defp dataset(payload, index), do: payload.chart |> datasets() |> Enum.at(index) |> data()
  defp datasets(chart), do: chart |> List.keyfind("datasets", 0) |> elem(1)
  defp data(dataset), do: dataset |> List.keyfind("data", 0) |> elem(1)
  defp label(dataset), do: dataset |> List.keyfind("label", 0) |> elem(1)

  test "payload builds signed chart series and balance rows from snapshots" do
    # 40 + 10 Wh each way: the middle interval straddles zero and splits into two triangles.
    snapshot!(360,
      pv1_power_w: 100,
      pv2_power_w: 50,
      pv3_power_w: 30,
      pv4_power_w: 20,
      battery_power_w: 20,
      active_power_w: 1200,
      pv_total_kwh: 10.0,
      battery_charge_total_kwh: 5.0,
      battery_discharge_total_kwh: 3.0
    )

    snapshot!(240,
      pv1_power_w: 150,
      pv2_power_w: 75,
      pv3_power_w: 45,
      pv4_power_w: 30,
      battery_power_w: -40,
      active_power_w: 1200,
      pv_total_kwh: 10.4,
      battery_charge_total_kwh: 5.1,
      battery_discharge_total_kwh: 3.1
    )

    snapshot!(120,
      pv1_power_w: 100,
      pv2_power_w: 50,
      pv3_power_w: 30,
      pv4_power_w: 20,
      battery_power_w: 30,
      active_power_w: -1200,
      pv_total_kwh: 10.8,
      battery_charge_total_kwh: 5.2,
      battery_discharge_total_kwh: 3.2
    )

    snapshot!(0,
      pv1_power_w: 120,
      pv2_power_w: 80,
      pv3_power_w: 40,
      pv4_power_w: 10,
      battery_power_w: -10,
      active_power_w: -1200,
      pv_total_kwh: 11.2,
      battery_charge_total_kwh: 5.4,
      battery_discharge_total_kwh: 3.3
    )

    payload = payload()

    assert payload.range == "24h"
    assert Enum.map(datasets(payload.chart), &label/1) == ["PV", "Akku", "Außensteckdose", "0 W"]
    assert dataset(payload, 0) == [200.0, 300.0, 200.0, 250.0]
    assert dataset(payload, 1) == [20.0, -40.0, 30.0, -10.0]
    assert dataset(payload, 2) == [1200.0, 1200.0, -1200.0, -1200.0]
    assert dataset(payload, 3) === [0, 0, 0, 0]

    rows = payload.balance_rows

    assert Enum.map(rows, & &1.label) ==
             [
               "PV-Erzeugung",
               "Akku geladen",
               "Akku entladen",
               "Ins Hausnetz geliefert",
               "Aus Hausnetz gezogen"
             ]

    assert Enum.map(rows, & &1.role) == ~w[solar battery battery grid grid]

    assert Enum.map(rows, & &1.value) == [
             "1,20 kWh",
             "0,40 kWh",
             "0,30 kWh",
             "0,05 kWh",
             "0,05 kWh"
           ]

    assert shares(payload) == [100.0, 33.3, 25.0, 4.2, 4.2]
    assert payload.outlet_average == "0 W"
    assert payload.message == nil
  end

  test "the mean outlet power is a plain figure with its direction in words" do
    for {watts, expected} <- [
          {1200, "liefert 1.200 W"},
          {-40.4, "zieht 40 W"},
          {0.4, "0 W"},
          {-0.4, "0 W"}
        ] do
      Repo.delete_all(Snapshot)
      snapshot!(120, active_power_w: watts)
      snapshot!(0, active_power_w: watts)

      assert payload().outlet_average == expected, "at #{watts} W"
    end
  end

  test "the outlet's mean power takes no share of the energy bars" do
    snapshot!(120, active_power_w: 3000, pv_total_kwh: 1.0)
    snapshot!(0, active_power_w: 3000, pv_total_kwh: 1.5)

    # 0,5 kWh PV and 0,1 kWh delivered: the 3 kW mean would set the scale if it counted.
    assert shares(payload()) == [100.0, 0.0, 0.0, 20.0, 0.0]
  end

  test "whichever outlet direction moved the most energy sets the bars' scale" do
    for {watts, shares} <- [
          {3000, [50.0, 0.0, 0.0, 100.0, 0.0]},
          {-3000, [50.0, 0.0, 0.0, 0.0, 100.0]}
        ] do
      Repo.delete_all(Snapshot)
      snapshot!(120, active_power_w: watts, pv_total_kwh: 1.0)
      snapshot!(0, active_power_w: watts, pv_total_kwh: 1.05)

      assert shares(payload()) == shares, "at #{watts} W"
    end
  end

  test "a range without energy draws empty bars" do
    snapshot!(120, pv_total_kwh: 1.0)
    snapshot!(0, pv_total_kwh: 1.0)

    assert shares(payload()) == List.duplicate(0.0, 5)
  end

  test "the battery can set the bars' scale too" do
    snapshot!(120, pv_total_kwh: 1.0, battery_charge_total_kwh: 5.0)
    snapshot!(0, pv_total_kwh: 1.1, battery_charge_total_kwh: 5.4)

    assert shares(payload()) == [25.0, 100.0, 0.0, 0.0, 0.0]
  end

  test "snapshots outside the range stay out" do
    snapshot!(25 * 3600, pv1_power_w: 900)
    snapshot!(0, pv1_power_w: 100)
    snapshot!(-300, pv1_power_w: 700)

    assert dataset(payload(), 0) == [100.0]
  end

  test "the range is one of 24h, 7d and 30d, anything else reads as 24h" do
    snapshot!(3 * 86_400, pv1_power_w: 300)
    snapshot!(20 * 86_400, pv1_power_w: 200)
    snapshot!(0, pv1_power_w: 100)

    assert dataset(payload("7d"), 0) == [300.0, 100.0]
    assert dataset(payload("30d"), 0) == [200.0, 300.0, 100.0]
    assert payload("1y").range == "24h"
    assert payload(["7d"]).range == "24h"
    assert payload(nil).range == "24h"
  end

  # Rails' `@now - 7.days` on a TimeWithZone steps calendar days on the local clock. Expected
  # bounds from Ruby (Time.zone = "Europe/Berlin"; (now - n.days).utc and now - (now - n.days)):
  #   2026-11-01 12:00 - 30.days = 2026-10-02 10:00 UTC, 2_595_600 s
  #   2026-11-01 12:00 -  7.days = 2026-10-25 11:00 UTC,   604_800 s
  #   2026-03-29 12:00 -  7.days = 2026-03-22 11:00 UTC,   601_200 s
  #   2026-03-29 12:00 - 30.days = 2026-02-27 11:00 UTC, 2_588_400 s
  #   2026-04-02 12:00:00.123456 - 7.days = 2026-03-26 11:00:00.123456 UTC
  #   2026-10-30 02:30 - 5.days = 2026-10-25 01:30 UTC (ambiguous: now's offset, +01:00)
  #   2026-04-03 02:30 - 5.days = 2026-03-29 01:30 UTC (gap: 02:30 → 03:30 +02:00)
  #   24.hours stays 86_400 s.
  test "7d and 30d start on the same local clock time, across both DST changes" do
    for {now, range, from} <- [
          {~U[2026-11-01 11:00:00.000000Z], "30d", ~U[2026-10-02 10:00:00.000000Z]},
          {~U[2026-11-01 11:00:00.000000Z], "7d", ~U[2026-10-25 11:00:00.000000Z]},
          {~U[2026-03-29 10:00:00.000000Z], "7d", ~U[2026-03-22 11:00:00.000000Z]},
          {~U[2026-03-29 10:00:00.000000Z], "30d", ~U[2026-02-27 11:00:00.000000Z]},
          {~U[2026-04-02 10:00:00.123456Z], "7d", ~U[2026-03-26 11:00:00.123456Z]},
          {~U[2026-11-01 11:00:00.000000Z], "24h", ~U[2026-10-31 11:00:00.000000Z]},
          {~U[2026-03-29 10:00:00.000000Z], "24h", ~U[2026-03-28 10:00:00.000000Z]}
        ] do
      assert History.from_time(range, now, "Europe/Berlin") == from, "#{range} before #{now}"
    end
  end

  test "the range's first snapshot is the one at its local-clock start" do
    now = ~U[2026-11-01 11:00:00.000000Z]

    for {seconds_ago, watts} <- [{2_595_601, 900}, {2_595_600, 300}, {0, 100}] do
      Repo.insert!(%Snapshot{taken_at: DateTime.add(now, -seconds_ago), pv1_power_w: watts * 1.0})
    end

    assert History.payload("30d", now, "Europe/Berlin") |> dataset(0) == [300.0, 100.0]
  end

  test "snapshots predating the third and fourth panel keep their PV series" do
    snapshot!(120, pv1_power_w: 100, pv2_power_w: 50)
    snapshot!(0, pv1_power_w: 120, pv2_power_w: 80)

    assert dataset(payload(), 0) == [150.0, 200.0]
  end

  test "sign-straddling interval contributes to both directions, not zero" do
    snapshot!(120, active_power_w: 1200)
    snapshot!(0, active_power_w: -1200)

    rows = payload().balance_rows

    # Averaging the endpoints first would report 0,00 kWh both ways.
    assert Enum.find(rows, &(&1.label == "Ins Hausnetz geliefert")).value == "0,01 kWh"
    assert Enum.find(rows, &(&1.label == "Aus Hausnetz gezogen")).value == "0,01 kWh"
  end

  test "a snapshot without active power takes the nearest reading's within two minutes" do
    snapshot!(120, pv1_power_w: 100)
    snapshot!(0, pv1_power_w: 100)

    for {seconds_ago, watts} <- [{150, 500.0}, {100, 111.0}, {5, 222.0}, {-130, 999.0}] do
      Repo.insert!(%Reading{
        taken_at: DateTime.add(@now, -seconds_ago),
        active_power_w: watts,
        pv_power_w: 0.0,
        battery_power_w: 0.0,
        battery_soc_pct: 50
      })
    end

    assert dataset(payload(), 2) == [111.0, 222.0]
  end

  test "chart_payload rounds series precisely and leaves the labels to the chart" do
    snapshot!(0,
      pv1_power_w: 100.111,
      pv2_power_w: 20.222,
      pv3_power_w: 3.033,
      pv4_power_w: 0.09,
      battery_power_w: 45.67,
      active_power_w: 12.34
    )

    payload = payload()

    assert Enum.map(payload.chart, &elem(&1, 0)) == ["times", "datasets"]
    assert dataset(payload, 0) == [123.5]
    assert dataset(payload, 1) == [45.7]
    assert dataset(payload, 2) == [12.3]
  end

  test "chart_payload carries each instant in epoch milliseconds, below the millisecond dropped" do
    for {usec_ago, ms} <- [{250_000, 750}, {250_500, 749}] do
      Repo.delete_all(Snapshot)
      taken_at = DateTime.add(@now, -usec_ago, :microsecond)
      Repo.insert!(%Snapshot{taken_at: taken_at, pv1_power_w: 100.0})

      assert payload().chart |> List.keyfind("times", 0) |> elem(1) ==
               [DateTime.to_unix(taken_at) * 1000 + ms]
    end
  end

  test "empty payload is stable" do
    payload = payload("7d")

    assert payload.range == "7d"
    assert Enum.map(payload.chart, &elem(&1, 0)) == ["times", "datasets"]
    assert payload.chart |> List.keyfind("times", 0) |> elem(1) == []
    assert Enum.map(datasets(payload.chart), &label/1) == ["PV", "Akku", "Außensteckdose", "0 W"]
    assert Enum.map(datasets(payload.chart), &data/1) == [[], [], [], []]
    assert payload.balance_rows == []
    assert payload.outlet_average == nil
    assert payload.message == "Keine Solakon-Historie"
  end
end
