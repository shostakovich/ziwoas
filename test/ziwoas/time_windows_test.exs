defmodule Ziwoas.TimeWindowsTest do
  use Ziwoas.DataCase

  import Ecto.Query

  alias Ziwoas.{Location, Repo, Solakon, SunCalendar, Weather}
  alias Ziwoas.Solakon.{PvHour, PvHourAggregator, Reading, Snapshot}
  alias Ziwoas.Weather.Record

  defp before(time), do: DateTime.add(usec(time), -1, :microsecond)
  defp after_(time), do: DateTime.add(usec(time), 1, :microsecond)

  defp record!(timestamp, attrs) do
    Repo.insert!(%Record{
      kind: Keyword.get(attrs, :kind, :historic),
      lat: 52.52,
      lon: 13.405,
      daytime: "day",
      timestamp: usec(timestamp),
      cloud_cover: Keyword.get(attrs, :cloud_cover)
    })
  end

  defp reading!(taken_at, pv_power_w \\ 300.0) do
    Repo.insert!(%Reading{
      taken_at: usec(taken_at),
      active_power_w: 0.0,
      pv_power_w: pv_power_w,
      battery_power_w: 0.0,
      battery_soc_pct: 50
    })
  end

  defp snapshot!(taken_at), do: Repo.insert!(%Snapshot{taken_at: usec(taken_at)})

  describe "Weather.today_hourly: from the start of this local hour to the end of tomorrow" do
    test "both bounds are in, a microsecond beyond either is out" do
      from = ~U[2026-05-04 10:00:00Z]
      to = ~U[2026-05-05 21:59:59.999999Z]

      for timestamp <- [before(from), from, to, after_(to)],
          do: record!(timestamp, kind: :forecast)

      assert Weather.today_hourly(~U[2026-05-04 10:34:00Z], "Europe/Berlin")
             |> Enum.map(& &1.timestamp) == [usec(from), usec(to)]
    end
  end

  describe "Solakon.fresh_reading: readings from `now - stale_after_s` on" do
    test "a reading exactly on the bound is fresh, one a microsecond older is not" do
      now = ~U[2026-06-20 12:00:00Z]
      since = ~U[2026-06-20 11:59:00Z]

      reading!(before(since))
      assert Solakon.fresh_reading(now, 60) == nil

      reading!(since)
      assert %Reading{taken_at: taken_at} = Solakon.fresh_reading(now, 60)
      assert taken_at == usec(since)
    end
  end

  describe "Solakon.history: snapshots of [now - 24 h, now]" do
    test "snapshots on either bound are in, a microsecond beyond is out" do
      from = ~U[2026-06-20 12:00:00Z]
      to = ~U[2026-06-21 12:00:00Z]

      for taken_at <- [before(from), from, to, after_(to)], do: snapshot!(taken_at)

      assert Solakon.history("24h", to, "UTC").times == [usec(from), usec(to)]
    end
  end

  describe "SunCalendar.year: the weather of a year, [local new year, next new year)" do
    test "the first instant of the year is in, the first of the next year is out" do
      location = Location.new("UTC", lat: 52.52, lon: 13.405)
      from = ~U[2026-01-01 00:00:00Z]
      to = ~U[2027-01-01 00:00:00Z]

      record!(before(from), cloud_cover: 10)
      record!(from, cloud_cover: 11)
      record!(before(~U[2026-12-31 23:00:00Z]), cloud_cover: 21)
      record!(to, cloud_cover: 22)

      year = SunCalendar.year(location, [], 2026)
      cloud = Enum.find(year.strips, &(&1.key == :cloud))

      assert cloud.values == %{{1, 0} => 11, {365, 22} => 21}
    end
  end

  describe "PvHourAggregator.aggregate_day: readings of [local midnight, next midnight)" do
    @day ~D[2026-04-10]
    @midnight ~U[2026-04-09 22:00:00Z]
    @next_midnight ~U[2026-04-10 22:00:00Z]

    defp readings!(taken_at, pv_power_w),
      do: for(_ <- 1..PvHourAggregator.min_readings(), do: reading!(taken_at, pv_power_w))

    test "readings on midnight count, those on the next midnight and just before do not" do
      readings!(before(@midnight), 50.0)
      readings!(@midnight, 100.0)
      readings!(@next_midnight, 900.0)

      PvHourAggregator.aggregate_day("Europe/Berlin", @day)

      assert [%PvHour{started_at: started_at, pv_power_w: 100.0, reading_count: 20}] =
               Repo.all(PvHour)

      assert started_at == usec(@midnight)
    end

    test "rewrites the PV hour on midnight and keeps the one on the next midnight" do
      Repo.insert!(%PvHour{started_at: usec(@midnight), pv_power_w: 1.0, reading_count: 20})
      Repo.insert!(%PvHour{started_at: usec(@next_midnight), pv_power_w: 2.0, reading_count: 20})

      PvHourAggregator.aggregate_day("Europe/Berlin", @day)

      assert Repo.all(from h in PvHour, order_by: h.started_at, select: h.pv_power_w) == [2.0]
    end
  end
end
