defmodule Ziwoas.SunCalendar.BuilderTest do
  use Ziwoas.DataCase

  alias Ziwoas.{LocalDay, Location, Repo}
  alias Ziwoas.Plugs.Sample5min
  alias Ziwoas.Solakon.PvHour
  alias Ziwoas.SunCalendar.{Builder, Year}
  alias Ziwoas.Weather.Record

  @lat 52.52
  @lon 13.405
  @april ~D[2026-04-10]
  @doy Date.day_of_year(@april)
  @may ~D[2026-05-10]
  @may_doy Date.day_of_year(@may)

  # Time.zone.local: an ambiguous hour is the earlier (summer-time) instant.
  defp utc(date, hour, minute \\ 0),
    do:
      date
      |> NaiveDateTime.new!(Time.new!(hour, minute, 0))
      |> LocalDay.to_instant("Europe/Berlin")
      |> DateTime.shift_zone!("Etc/UTC")

  defp plug_bucket(hour, energy_wh, opts \\ []) do
    Repo.insert!(%Sample5min{
      plug_id: Keyword.get(opts, :plug_id, "bkw"),
      bucket_ts:
        DateTime.to_unix(utc(Keyword.get(opts, :date, @may), hour, Keyword.get(opts, :minute, 0))),
      avg_power_w: energy_wh * 12,
      energy_delta_wh: energy_wh,
      sample_count: 10
    })
  end

  defp pv_hour_at(started_at, watts),
    do: Repo.insert!(%PvHour{started_at: usec(started_at), pv_power_w: watts, reading_count: 120})

  defp pv_hour(hour, watts, date \\ @april), do: pv_hour_at(utc(date, hour), watts)

  defp weather_at(timestamp, solar, cloud, opts \\ []) do
    Repo.insert!(%Record{
      kind: Keyword.get(opts, :kind, :historic),
      daytime: "day",
      lat: Keyword.get(opts, :lat, @lat),
      lon: Keyword.get(opts, :lon, @lon),
      timestamp: usec(timestamp),
      solar: solar,
      cloud_cover: cloud
    })
  end

  defp weather(hour, solar, cloud, opts \\ []),
    do: weather_at(utc(Keyword.get(opts, :date, @april), hour), solar, cloud, opts)

  defp location(opts \\ []) do
    Location.new(Keyword.get(opts, :zone, "Europe/Berlin"),
      lat: Keyword.get(opts, :lat, @lat),
      lon: Keyword.get(opts, :lon, @lon)
    )
  end

  defp build(opts \\ []),
    do:
      Builder.build(
        location(opts),
        Keyword.get(opts, :producer_ids, []),
        Keyword.get(opts, :year, 2026)
      )

  defp strip(year, key), do: Enum.find(year.strips, &(&1.key == key))
  defp day(year, doy), do: Enum.find(year.days, &(&1.doy == doy))

  test "puts the hourly PV mean into the cell of its local clock hour" do
    pv_hour(12, 640.0)

    assert %{values: values, unit: "W", ramp: :amber, title: "PV-Leistung"} = strip(build(), :pv)
    assert values == %{{@doy, 12} => 640.0}
  end

  test "turns the hourly means into the day's PV energy, the best day the year's maximum" do
    pv_hour(11, 100.0, ~D[2026-01-15])
    pv_hour(11, 500.0)
    pv_hour(12, 700.0)
    pv_hour(11, 200.0, ~D[2026-11-01])
    year = build()

    assert_in_delta day(year, @doy).pv_kwh, 1.2, 1.0e-9
    assert_in_delta year.max_kwh, 1.2, 1.0e-9
  end

  test "reads irradiance as power per area and cloud cover as given; sums and averages the day" do
    weather(11, 0.4, 20)
    weather(12, 0.62, 21)
    weather(13, nil, nil)
    year = build()

    assert_in_delta strip(year, :irradiance).values[{@doy, 12}], 620.0, 1.0e-9

    assert %{values: %{{@doy, 12} => 21}, max: 100.0, unit: "%", ramp: :grey} =
             strip(year, :cloud)

    assert %{unit: "W/m²", ramp: :blue, title: "Einstrahlung"} = strip(year, :irradiance)
    assert_in_delta day(year, @doy).irradiance_kwh_per_m2, 1.02, 1.0e-9
    assert day(year, @doy).cloud_avg == 20.5
  end

  test "leaves a day without data empty rather than at zero, and covers every day" do
    pv_hour(12, 640.0)
    year = build()

    assert %{pv_kwh: nil, irradiance_kwh_per_m2: nil, cloud_avg: nil, date: ~D[2026-04-11]} =
             day(year, @doy + 1)

    assert year.year == 2026
    assert length(year.days) == 365
    assert length(build(year: 2024).days) == 366
  end

  test "rounds the strip maximum up to the next fifty, from the highest reading, and keeps one above zero" do
    assert strip(build(), :pv).max === 50.0

    pv_hour(10, 300.0)
    pv_hour(11, 612.0)
    pv_hour(12, 500.0)
    weather(12, 0.81, 10)

    assert strip(build(), :pv).max === 650.0
    assert strip(build(), :irradiance).max === 850.0
  end

  test "shows the base hours and widens them for data outside" do
    assert build().hours == {3, 22}

    pv_hour(1, 5.0)
    pv_hour(23, 7.0)

    assert build().hours == {1, 23}
  end

  test "widens the hours so the sun lines stay inside the strip, from sunrise or sunset" do
    madrid = Builder.build(Location.new("Europe/Madrid", lat: 43.4, lon: -8.4), [], 2026)
    {first, last} = madrid.hours
    assert first <= madrid.lines.rise |> Enum.map(&elem(&1, 1)) |> Enum.min()
    assert last + 1 >= madrid.lines.set |> Enum.map(&elem(&1, 1)) |> Enum.max()

    assert Builder.build(Location.new("Europe/Oslo", lat: 69.6, lon: 18.9), [], 2026).hours ==
             {0, 24}

    assert Builder.build(Location.new("Europe/Oslo", lat: 69.6, lon: 40.0), [], 2026).hours ==
             {0, 24}

    assert Builder.build(Location.new("UTC", lat: 0.0, lon: 0.0), [], 2026).hours == {3, 22}
  end

  test "fills the time before the inverter from the producer plug, and marks the seam" do
    plug_bucket(11, 200.0)
    plug_bucket(12, 50.0)
    plug_bucket(12, 30.0, minute: 5)
    plug_bucket(12, 50.0, date: ~D[2026-06-20])
    pv_hour(12, 640.0, ~D[2026-06-20])
    year = build(producer_ids: ["bkw"])
    values = strip(year, :pv).values

    assert values[{@may_doy, 12}] == 80.0
    assert values[{Date.day_of_year(~D[2026-06-20]), 12}] == 640.0
    assert map_size(values) == 3
    assert_in_delta day(year, @may_doy).pv_kwh, 0.28, 1.0e-9
    assert year.seam == ~D[2026-06-20]
  end

  test "ignores plugs that do not produce, and takes the whole plug history without an inverter" do
    plug_bucket(12, 50.0)

    assert strip(build(producer_ids: ["fridge"]), :pv).values == %{}
    assert strip(build(), :pv).values == %{}

    year = build(producer_ids: ["bkw"])
    assert strip(year, :pv).values == %{{@may_doy, 12} => 50.0}
    assert year.seam == nil
  end

  test "has no seam when the plug never stood in" do
    pv_hour(12, 640.0, ~D[2026-06-20])
    assert build(producer_ids: ["bkw"]).seam == nil
  end

  test "ignores hours and records outside the year, elsewhere, or forecast" do
    pv_hour(12, 640.0, ~D[2025-12-31])
    pv_hour(12, 640.0, ~D[2027-01-01])
    weather(12, 0.5, 10, date: ~D[2025-12-31])
    weather(12, 0.5, 10, lat: 48.1, lon: 11.6)
    weather(13, 9.9, 99, kind: :forecast)
    year = build()

    assert Year.empty?(year)
    assert strip(year, :irradiance).values == %{}
  end

  test "is empty while no PV hour exists, whatever the weather" do
    weather(12, 0.62, 40)
    assert Year.empty?(build())

    pv_hour(12, 640.0)
    refute Year.empty?(build())
  end

  test "draws the sun lines for a configured location only, and reads weather only then" do
    weather(12, 0.62, 40)

    assert length(build().lines.rise) == 365 + 2
    year = build(lat: nil, lon: nil)
    assert year.lines.rise == []
    assert strip(year, :irradiance).values == %{}
  end

  test "counts both repeated hours of the autumn clock change, the later one winning the cell" do
    date = ~D[2026-10-25]
    pv_hour_at(DateTime.add(utc(date, 2), 3600), 300.0)
    pv_hour(2, 100.0, date)
    weather_at(DateTime.add(utc(date, 2), 3600), 0.9, 90)
    weather(2, 0.1, 10, date: date)
    year = build()

    assert_in_delta day(year, Date.day_of_year(date)).pv_kwh, 0.4, 1.0e-9
    assert strip(year, :pv).values[{Date.day_of_year(date), 2}] == 300.0
    assert_in_delta strip(year, :irradiance).values[{Date.day_of_year(date), 2}], 900.0, 1.0e-9
  end

  test "reads local times and the year's bounds in the builder's own zone" do
    honolulu = Location.new("Pacific/Honolulu")
    # 2026-04-10 23:00 UTC is 2026-04-10 13:00 in Honolulu (UTC-10, no DST).
    pv_hour_at(~U[2026-04-10 23:00:00Z], 500.0)
    pv_hour_at(~U[2026-01-01 09:00:00Z], 111.0)
    pv_hour_at(~U[2026-01-01 10:00:00Z], 222.0)
    pv_hour_at(~U[2027-01-01 09:59:59Z], 333.0)
    pv_hour_at(~U[2027-01-01 10:00:00Z], 444.0)

    assert strip(Builder.build(honolulu, [], 2026), :pv).values == %{
             {Date.day_of_year(@april), 13} => 500.0,
             {1, 0} => 222.0,
             {365, 23} => 333.0
           }
  end

  test "names the year of the newest PV hour, else the current one" do
    now = ~U[2026-10-05 10:00:00Z]
    assert Builder.latest_year(location(), now) == 2026

    pv_hour_at(~U[2025-12-31 23:30:00Z], 1.0)
    assert Builder.latest_year(location(), now) == 2026
    assert Builder.latest_year(location(zone: "UTC"), now) == 2025
  end
end
