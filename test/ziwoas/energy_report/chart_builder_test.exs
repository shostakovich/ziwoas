defmodule Ziwoas.EnergyReport.ChartBuilderTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Energy, Location, Repo}
  alias Ziwoas.EnergyReport.{ChartBuilder, DailyPoint}
  alias Ziwoas.Plugs.{DailyTotal, Plug, Roster, Sample5min}

  @zone "Europe/Berlin"

  @roster Roster.new([
            %Plug{id: "bkw", name: "BKW", role: :producer},
            %Plug{id: "fridge", name: "Fridge", role: :consumer},
            %Plug{id: "tv", name: "TV", role: :consumer}
          ])

  defp point(date, produced_wh, consumed_wh, self_consumed_wh) do
    %DailyPoint{
      date: date,
      produced: Energy.wh(produced_wh),
      consumed: Energy.wh(consumed_wh),
      self_consumed: Energy.wh(self_consumed_wh),
      covered: true
    }
  end

  defp total!(plug_id, date, energy_wh) do
    Repo.insert!(%DailyTotal{plug_id: plug_id, date: date, energy_wh: energy_wh * 1.0})
  end

  defp bucket!(plug_id, %DateTime{} = at, avg_power_w) do
    Repo.insert!(%Sample5min{
      plug_id: plug_id,
      bucket_ts: DateTime.to_unix(at),
      avg_power_w: avg_power_w * 1.0,
      energy_delta_wh: 0.0,
      sample_count: 1
    })
  end

  defp payload(points, first, last) do
    rows = Repo.all(DailyTotal)
    ChartBuilder.payload(@roster, Location.new(@zone), points, rows, {first, last})
  end

  defp dates(first, last), do: first |> Date.range(last) |> Enum.map(&Date.to_iso8601/1)

  describe "the daily chart" do
    test "one label per day across a month's end, values in kWh to three decimals" do
      points = [
        point("2026-03-30", 1234.5678, 800.0, 400.0),
        DailyPoint.uncovered("2026-03-31"),
        point("2026-04-01", 0.4, 1000.0, 0.4)
      ]

      daily = payload(points, ~D[2026-03-30], ~D[2026-04-01]).daily

      assert daily.labels == ["30.03.", "31.03.", "01.04."]
      assert daily.produced_kwh == [1.235, 0.0, 0.0]
      assert daily.consumed_kwh == [0.8, 0.0, 1.0]
      assert daily.balance_kwh == [0.435, 0.0, -1.0]
      refute Map.has_key?(daily, :weather)
    end

    test "ratios per day in percent; an uncovered day has none" do
      points = [point("2026-03-30", 2000.0, 800.0, 600.0), DailyPoint.uncovered("2026-03-31")]

      assert payload(points, ~D[2026-03-30], ~D[2026-03-31]).daily.ratios == [
               %{date: "2026-03-30", autarky_pct: 75.0, self_consumption_pct: 30.0},
               %{date: "2026-03-31", autarky_pct: nil, self_consumption_pct: nil}
             ]
    end

    test "a series per consumer in config order, 0 on days without a total" do
      total!("tv", "2026-03-31", 1500)
      total!("fridge", "2026-03-30", 400)
      total!("bkw", "2026-03-30", 9000)
      points = [point("2026-03-30", 0, 0, 0), point("2026-03-31", 0, 0, 0)]

      assert payload(points, ~D[2026-03-30], ~D[2026-03-31]).daily.consumer_series == [
               %{plug_id: "fridge", name: "Fridge", data: [0.4, 0.0]},
               %{plug_id: "tv", name: "TV", data: [0.0, 1.5]}
             ]
    end
  end

  describe "the detail chart up to seven days" do
    test "one day: local clock labels, millisecond times, producers positive" do
      bucket!("bkw", ~U[2026-06-01 10:00:00Z], -812.34)
      bucket!("fridge", ~U[2026-06-01 10:00:00Z], 95.06)
      bucket!("fridge", ~U[2026-06-01 10:05:00Z], 90.0)

      detail = payload([], ~D[2026-06-01], ~D[2026-06-01]).detail

      assert detail.chart_type == "line"
      assert detail.labels == ["12:00", "12:05"]
      assert detail.times == [1_780_308_000_000, 1_780_308_300_000]

      assert detail.series == [
               %{plug_id: "bkw", name: "BKW", role: "producer", data: [812.3, nil]},
               %{plug_id: "fridge", name: "Fridge", role: "consumer", data: [95.1, 90.0]}
             ]
    end

    test "several days carry the date in each label and change day at local midnight" do
      bucket!("fridge", ~U[2026-06-01 21:55:00Z], 50)
      bucket!("fridge", ~U[2026-06-01 22:00:00Z], 50)
      # Outside the range: the local day before it, and after it.
      bucket!("fridge", ~U[2026-05-31 21:55:00Z], 50)
      bucket!("fridge", ~U[2026-06-02 22:00:00Z], 50)

      detail = payload([], ~D[2026-06-01], ~D[2026-06-02]).detail

      assert detail.labels == ["01.06. 23:55", "02.06. 00:00"]
    end

    test "the clocks going forward leave no 02:00 hour" do
      bucket!("fridge", ~U[2026-03-29 00:55:00Z], 50)
      bucket!("fridge", ~U[2026-03-29 01:00:00Z], 50)

      assert payload([], ~D[2026-03-29], ~D[2026-03-29]).detail.labels == ["01:55", "03:00"]
    end

    test "the clocks going back show the repeated hour twice, the times apart" do
      bucket!("fridge", ~U[2026-10-25 00:30:00Z], 50)
      bucket!("fridge", ~U[2026-10-25 01:30:00Z], 50)
      bucket!("fridge", ~U[2026-10-25 22:55:00Z], 50)

      detail = payload([], ~D[2026-10-25], ~D[2026-10-25]).detail

      assert detail.labels == ["02:30", "02:30", "23:55"]
      assert [a, b, _] = detail.times
      assert b - a == 3_600_000
    end

    test "a plug without any value in the range has no series" do
      bucket!("fridge", ~U[2026-06-01 10:00:00Z], 50)

      assert [%{plug_id: "fridge"}] = payload([], ~D[2026-06-01], ~D[2026-06-01]).detail.series
    end
  end

  test "beyond seven days the detail chart is average power per day" do
    for date <- dates(~D[2026-03-25], ~D[2026-04-01]), do: total!("fridge", date, 2400)
    total!("bkw", "2026-03-29", 4812)

    detail = payload([], ~D[2026-03-25], ~D[2026-04-01]).detail

    assert detail.chart_type == "bar"
    assert hd(detail.labels) == "25.03." and List.last(detail.labels) == "01.04."
    assert Enum.at(detail.times, 4) == DateTime.to_unix(~U[2026-03-28 23:00:00Z]) * 1000
    assert Enum.at(detail.times, 5) == DateTime.to_unix(~U[2026-03-29 22:00:00Z]) * 1000

    assert [bkw, fridge] = detail.series
    assert bkw.data == [nil, nil, nil, nil, 200.5, nil, nil, nil]
    assert fridge.data == List.duplicate(100.0, 8)
  end
end
