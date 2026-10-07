defmodule Ziwoas.Shading.BuilderTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Location, Repo, Shading}
  alias Ziwoas.Shading.{Builder, SunPaths}
  alias Ziwoas.Solakon.PvHour
  alias Ziwoas.Weather.Record

  @lat 52.52
  @lon 13.405
  @july ~D[2026-07-01]
  @now ~U[2026-10-05 10:00:00.000000Z]

  defp at(date, hour),
    do:
      date
      |> DateTime.new!(Time.new!(hour, 0, 0), "Europe/Berlin")
      |> usec()

  defp pv_hour(hour, watts, opts \\ []) do
    [p1, p2, p3, p4] = Keyword.get(opts, :panels, [100.0, 100.0, 100.0, 100.0])

    Repo.insert!(%PvHour{
      started_at: at(Keyword.get(opts, :date, @july), hour),
      pv_power_w: watts,
      reading_count: 120,
      pv1_power_w: p1,
      pv2_power_w: p2,
      pv3_power_w: p3,
      pv4_power_w: p4
    })
  end

  # `hour` is the hour the record sums up; Bright Sky stamps its end.
  defp weather(hour, opts) do
    Repo.insert!(%Record{
      kind: Keyword.get(opts, :kind, :historic),
      daytime: "day",
      lat: Keyword.get(opts, :lat, @lat),
      lon: Keyword.get(opts, :lon, @lon),
      timestamp: DateTime.add(at(Keyword.get(opts, :date, @july), hour), 3600),
      solar: Keyword.fetch!(opts, :solar)
    })
  end

  defp build(opts \\ []) do
    location =
      Location.new(Keyword.get(opts, :zone, "Europe/Berlin"),
        lat: Keyword.get(opts, :lat, @lat),
        lon: Keyword.get(opts, :lon, @lon)
      )

    Builder.build(location, Keyword.get(opts, :now, @now))
  end

  defp profile(report), do: hd(report.profiles)
  defp points(profile, key), do: Shading.curve(profile, key).points

  test "reads the day's shape from the PV hours alone" do
    pv_hour(12, 640.0)

    assert [%{month: 7} = profile] = build().profiles
    assert points(profile, :measured) == [{12, 640.0}]
  end

  test "joins the irradiance summed over the PV hour onto it, not the hour before" do
    pv_hour(12, 400.0)
    weather(12, solar: 0.5)
    assert build() |> profile() |> points(:expected) == [{12, 400.0}]

    Repo.delete_all(Record)
    weather(11, solar: 0.5)
    assert build() |> profile() |> points(:expected) == []
  end

  test "reads the irradiance of the hour that starts with the last PV hour" do
    for hour <- [12, 13], do: pv_hour(hour, 400.0) && weather(hour, solar: 0.5)

    assert build() |> profile() |> points(:expected) == [{12, 400.0}, {13, 400.0}]
  end

  test "ignores the irradiance measured somewhere else, and the station's forecast" do
    pv_hour(12, 400.0)
    weather(12, solar: 0.5, lat: 48.15, lon: 11.26)
    assert build() |> profile() |> points(:expected) == []

    pv_hour(12, 400.0, date: Date.add(@july, 1))
    weather(12, solar: 0.5)
    weather(12, solar: 0.5, date: Date.add(@july, 1))
    weather(12, solar: 2.0, date: Date.add(@july, 1), kind: :forecast)
    assert build() |> profile() |> points(:expected) == [{12, 400.0}]
  end

  test "calibrates on the best hour and shrugs off a single outlier" do
    for index <- 0..19 do
      pv_hour(12, 400.0, date: Date.add(@july, index))
      weather(12, solar: 0.5, date: Date.add(@july, index))
    end

    pv_hour(12, 2000.0, date: ~D[2026-08-01])
    weather(12, solar: 0.5, date: ~D[2026-08-01])

    august = Enum.find(build().profiles, &(&1.month == 8))

    # 0.8 W per W/m², the ratio of the twenty ordinary hours, not the outlier's 4.0.
    assert points(august, :expected) == [{12, 400.0}]
  end

  test "calibrates only on the hours bright enough, the threshold included" do
    pv_hour(12, 400.0)
    weather(12, solar: 0.5)
    pv_hour(12, 900.0, date: Date.add(@july, 1))
    weather(12, solar: 0.2, date: Date.add(@july, 1))

    # The dim hour's ratio of 4.5 never calibrates; 350 W/m² average at 0.8 W per W/m².
    assert build() |> profile() |> points(:expected) == [{12, 280.0}]

    Repo.delete_all(PvHour)
    Repo.delete_all(Record)
    pv_hour(12, 400.0)
    weather(12, solar: 0.5)
    pv_hour(12, 600.0, date: Date.add(@july, 1))
    weather(12, solar: 0.3, date: Date.add(@july, 1))

    assert build() |> profile() |> points(:expected) == [{12, 800.0}]
  end

  test "takes the best hour from the top of the sorted ratios" do
    for index <- 0..20 do
      pv_hour(12, 2100.0 - index * 100, date: Date.add(@july, index))
      weather(12, solar: 0.5, date: Date.add(@july, index))
    end

    # Ratios 0.2 to 4.2; the 95th percentile sits on 4.0, over 500 W/m² average.
    assert build() |> profile() |> points(:expected) == [{12, 2000.0}]
  end

  test "places the hour where the sun stood over the house" do
    for index <- 0..2 do
      pv_hour(12, 400.0, date: Date.add(@july, index))
      weather(12, solar: 0.5, date: Date.add(@july, index))
    end

    assert [%{azimuth: 160, elevation: 55, hours: 3}] = build().map.bins
  end

  test "draws the sun paths of the current year in the location's zone" do
    pv_hour(12, 400.0, date: ~D[2025-07-01])

    assert Enum.map(build().map.paths, & &1.label) == ["21.6.", "21.3. / 23.9.", "21.12."]

    # 22:00 UTC on Dec 31st is already Jan 1st in Pacific/Auckland (+13h).
    auckland = Location.new("Pacific/Auckland", lat: @lat, lon: @lon)

    assert build(zone: "Pacific/Auckland", now: ~U[2026-12-31 22:00:00Z]).map.paths ==
             SunPaths.build(auckland, 2027)
  end

  test "keeps the measured curve without a location, and nothing that needs one" do
    pv_hour(12, 400.0)

    report = build(lat: nil, lon: nil)

    assert report.map.bins == []
    assert report.map.paths == []
    assert points(profile(report), :measured) == [{12, 400.0}]
    assert points(profile(report), :theory) == []
  end

  test "counts the panels of the days on which all four delivered" do
    pv_hour(12, 400.0, panels: [100.0, 100.0, 0.0, 0.0])
    pv_hour(12, 400.0, panels: [100.0, 100.0, 50.0, 50.0], date: Date.add(@july, 1))

    panels = build().panels

    assert panels.days == 1
    assert Shading.curve(panels, :pv3).points == [{12, 50.0}]
  end

  test "reads the clock in the timezone it was given" do
    pv_hour(12, 640.0)

    assert build(zone: "UTC") |> profile() |> points(:measured) == [{10, 640.0}]
  end

  test "is empty while no PV hour has been aggregated" do
    assert Shading.Report.empty?(build())
  end

  test "has no best hour while the array produced nothing under a bright sky" do
    for index <- 0..2 do
      pv_hour(12, 0.0, date: Date.add(@july, index))
      weather(12, solar: 0.5, date: Date.add(@july, index))
    end

    report = build()

    assert report.map.bins == []
    assert points(profile(report), :expected) == []
    assert points(profile(report), :theory) == []
  end

  test "lists the PV hours chronologically regardless of insertion order" do
    pv_hour(18, 900.0)
    pv_hour(6, 100.0)

    assert build() |> profile() |> points(:measured) |> Enum.map(&elem(&1, 0)) ==
             [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18] -- Enum.to_list(7..17)
  end
end
