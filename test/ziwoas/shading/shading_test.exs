defmodule Ziwoas.ShadingTest do
  use ExUnit.Case, async: true

  alias Ziwoas.{Location, Shading}
  alias Ziwoas.Shading.{ClearSky, DailyProfiles, Hour, PanelCurves, SunPaths, YieldMap}

  defp at(date, clock), do: DateTime.new!(date, Time.new!(clock, 0, 0), "Europe/Berlin")

  defp points(report, key), do: Shading.curve(report, key).points

  describe "YieldMap" do
    defp map_hour(opts) do
      %Hour{
        time: at(~D[2026-07-01], Keyword.get(opts, :clock, 12)),
        pv_w: Keyword.get(opts, :pv_w, 400.0),
        irradiance_w_per_m2: Keyword.get(opts, :irradiance, 500.0),
        panels: [],
        azimuth: Keyword.fetch!(opts, :azimuth),
        elevation: Keyword.fetch!(opts, :elevation)
      }
    end

    defp map(hours, best_ratio \\ 1.0, paths \\ []), do: YieldMap.build(hours, paths, best_ratio)
    defp three(opts), do: List.duplicate(map_hour(opts), 3)

    test "puts an hour into the field of five degrees it fell into" do
      map = map(three(azimuth: 143.2, elevation: 47.9))

      assert map.bin_size == 5
      assert Enum.map(map.bins, &{&1.azimuth, &1.elevation}) == [{140, 45}]
    end

    test "takes the median of a field as a share of the best hour, the middle two of an even one" do
      odd =
        for {w, a} <- [{700.0, 141.0}, {100.0, 142.0}, {400.0, 143.0}],
            do: map_hour(azimuth: a, elevation: 46.0, pv_w: w)

      assert [%{share: share, hours: 3}] = map(odd).bins
      assert_in_delta share, 0.8, 0.001

      even =
        for w <- [600.0, 100.0, 200.0, 300.0],
            do: map_hour(azimuth: 141.0, elevation: 46.0, pv_w: w)

      assert_in_delta hd(map(even).bins).share, 0.5, 0.001

      six =
        for w <- [600.0, 500.0, 100.0, 200.0, 300.0, 400.0],
            do: map_hour(azimuth: 141.0, elevation: 46.0, pv_w: w)

      assert_in_delta hd(map(six).bins).share, 0.7, 0.001

      assert_in_delta hd(map(three(azimuth: 100.0, elevation: 20.0), 2.0).bins).share, 0.4, 0.001
    end

    test "draws no field before a best hour is known, nor one with fewer than three hours" do
      assert map(three(azimuth: 100.0, elevation: 20.0), nil).bins == []
      assert map(List.duplicate(map_hour(azimuth: 100.0, elevation: 20.0), 2)).bins == []
    end

    test "skips dim, unmeasured, unplaced hours and the sun below the horizon" do
      assert map(
               three(azimuth: 100.0, elevation: 20.0, irradiance: 99.9) ++
                 three(azimuth: 100.0, elevation: -0.5)
             ).bins == []

      assert map(three(azimuth: 100.0, elevation: 20.0, irradiance: nil)).bins == []
      assert map(three(azimuth: nil, elevation: nil)).bins == []
      assert [%{hours: 3}] = map(three(azimuth: 100.0, elevation: 20.0, irradiance: 100.0)).bins
      assert [%{azimuth: 100, elevation: 0}] = map(three(azimuth: 100.0, elevation: 0.5)).bins
    end

    test "names the hours of the day a field was measured in, and carries its sun paths" do
      hours =
        for clock <- [9, 7, 10, 8], do: map_hour(azimuth: 100.0, elevation: 20.0, clock: clock)

      assert [%{first_hour: 7, last_hour: 10}] = map(hours).bins

      paths = [%Shading.Path{day: :summer_solstice, points: [], dots: []}]
      assert map([], 1.0, paths).paths == paths
    end
  end

  describe "DailyProfiles" do
    defp day_hour(clock, opts \\ []) do
      %Hour{
        time: at(Keyword.get(opts, :date, ~D[2026-07-01]), clock),
        pv_w: Keyword.get(opts, :pv_w, 400.0),
        irradiance_w_per_m2: Keyword.get(opts, :irradiance, 500.0),
        panels: [],
        azimuth: 180.0,
        elevation: Keyword.get(opts, :elevation, 30.0)
      }
    end

    defp profiles(hours, best_ratio \\ 1.0), do: DailyProfiles.build(hours, best_ratio)
    defp profile(hours, best_ratio \\ 1.0), do: hd(profiles(hours, best_ratio))

    test "gives every month its own profile, in the order of the year" do
      profiles =
        profiles([day_hour(12, date: ~D[2026-08-03]), day_hour(12, date: ~D[2026-05-03])])

      assert Enum.map(profiles, & &1.month) == [5, 8]
      assert Enum.map(profiles, & &1.days) == [1, 1]
      assert profiles([]) == []
    end

    test "averages the measured power of one clock hour over the month's days" do
      profile =
        profile([
          day_hour(11, pv_w: 200.0),
          day_hour(11, pv_w: 400.0, date: ~D[2026-07-02]),
          day_hour(12, pv_w: 900.0)
        ])

      assert points(profile, :measured) == [{11, 300.0}, {12, 900.0}]
      assert profile.days == 2
    end

    test "scales irradiance and the cloudless sky by the best hour" do
      assert points(profile([day_hour(12, irradiance: 500.0)], 0.8), :expected) == [{12, 400.0}]
      assert [{12, theory}] = points(profile([day_hour(12, elevation: 90.0)], 0.5), :theory)
      assert_in_delta theory, 517.5, 0.5
    end

    test "leaves out what is unknown: irradiance, sun position, best hour" do
      assert points(profile([day_hour(12, irradiance: nil)]), :expected) == []
      assert points(profile([day_hour(12, elevation: nil)]), :theory) == []

      profile = profile([day_hour(12)], nil)
      assert points(profile, :expected) == []
      assert points(profile, :theory) == []
      assert points(profile, :measured) == [{12, 400.0}]
    end

    test "averages over the days the station measured, ignoring the rest" do
      profile =
        profile([
          day_hour(12, irradiance: nil),
          day_hour(12, irradiance: 500.0, date: ~D[2026-07-02])
        ])

      assert points(profile, :expected) == [{12, 500.0}]

      paired = day_hour(12, pv_w: 300.0, irradiance: 400.0)
      measured_only = day_hour(12, pv_w: 900.0, irradiance: nil, date: ~D[2026-07-02])
      profile = profile([paired, measured_only])
      assert points(profile, :measured) == [{12, 300.0}]
      assert profile.days == 1

      profile =
        profile([day_hour(11, irradiance: nil), day_hour(12, pv_w: 800.0, irradiance: nil)])

      assert points(profile, :measured) == [{11, 400.0}, {12, 800.0}]
    end

    test "orders the hours and cuts the night off the day" do
      assert profile([day_hour(12), day_hour(10), day_hour(11)])
             |> points(:measured)
             |> Enum.map(&elem(&1, 0)) == [10, 11, 12]

      night =
        for clock <- [2, 23], do: day_hour(clock, pv_w: 0.0, irradiance: 0.0, elevation: -20.0)

      assert profile(night ++ [day_hour(12)]) |> points(:theory) |> Enum.map(&elem(&1, 0)) == [12]

      dark = for clock <- [8, 12], do: day_hour(clock, pv_w: 0.0, irradiance: 0.0, elevation: nil)
      assert points(profile(dark), :measured) == []

      edges = [
        day_hour(8, pv_w: 0.0, irradiance: 500.0, elevation: nil),
        day_hour(10, irradiance: 0.0, elevation: nil),
        day_hour(12, pv_w: 0.0, irradiance: 500.0, elevation: nil),
        day_hour(14, irradiance: 0.0, elevation: nil)
      ]

      assert profile(edges) |> points(:measured) |> Enum.map(&elem(&1, 0)) == [8, 10, 12, 14]

      assert profile([day_hour(10), day_hour(11, pv_w: 0.0), day_hour(12)])
             |> points(:measured)
             |> length() == 3
    end
  end

  describe "PanelCurves" do
    defp panel_hour(clock, panels, date \\ ~D[2026-09-01]) do
      %Hour{
        time: at(date, clock),
        pv_w: 0.0,
        irradiance_w_per_m2: 500.0,
        panels: panels,
        azimuth: 180.0,
        elevation: 30.0
      }
    end

    test "averages each panel over the clock hours of the counted days" do
      panels =
        PanelCurves.build([
          panel_hour(11, [100.0, 200.0, 300.0, 400.0]),
          panel_hour(11, [300.0, 200.0, 300.0, 400.0], ~D[2026-09-02]),
          panel_hour(12, [500.0, 600.0, 700.0, 800.0])
        ])

      assert points(panels, :pv1) == [{11, 200.0}, {12, 500.0}]
      assert points(panels, :pv2) == [{11, 200.0}, {12, 600.0}]
      assert panels.days == 2
      assert panels.since == ~D[2026-09-01]
    end

    test "counts only days on which every panel delivered, at least once" do
      silent = panel_hour(12, [500.0, 600.0, 0.0, 0.0], ~D[2026-08-01])
      full = panel_hour(12, [100.0, 100.0, 100.0, 100.0])
      panels = PanelCurves.build([silent, full])

      assert {points(panels, :pv1), panels.days, panels.since} ==
               {[{12, 100.0}], 1, ~D[2026-09-01]}

      morning = panel_hour(8, [50.0, 50.0, 0.0, 0.0])
      noon = panel_hour(12, [400.0, 400.0, 400.0, 400.0])
      assert points(PanelCurves.build([morning, noon]), :pv3) == [{8, 0.0}, {12, 400.0}]
      assert PanelCurves.build([panel_hour(12, [0.5, 400.0, 400.0, 400.0])]).days == 1
    end

    test "skips the hours with missing or too few panels" do
      assert Shading.Panels.empty?(PanelCurves.build([panel_hour(12, [nil, nil, nil, nil])]))

      assert Shading.Panels.empty?(
               PanelCurves.build([panel_hour(12, [100.0, 100.0, 100.0, nil])])
             )

      assert Shading.Panels.empty?(PanelCurves.build([panel_hour(12, [100.0, 200.0])]))
    end

    test "names the earliest day, orders the hours, cuts the night, and is empty without hours" do
      late = panel_hour(12, [400.0, 400.0, 400.0, 400.0], ~D[2026-09-02])
      early = panel_hour(10, [200.0, 200.0, 200.0, 200.0], ~D[2026-09-01])
      panels = PanelCurves.build([late, early])
      assert panels.since == ~D[2026-09-01]
      assert points(panels, :pv1) == [{10, 200.0}, {12, 400.0}]

      night = panel_hour(2, [0.0, 0.0, 0.0, 0.0])

      assert PanelCurves.build([night, panel_hour(12, [400.0, 400.0, 400.0, 400.0])])
             |> points(:pv1)
             |> length() == 1

      empty = PanelCurves.build([])
      assert {Shading.Panels.empty?(empty), empty.days, empty.since} == {true, 0, nil}
    end
  end

  describe "ClearSky" do
    test "follows Haurwitz from the horizon to the zenith" do
      assert ClearSky.w_per_m2(0.0) === 0.0
      assert ClearSky.w_per_m2(-5.0) === 0.0
      assert_in_delta ClearSky.w_per_m2(90.0), 1035.1, 0.1
      assert_in_delta ClearSky.w_per_m2(30.0), 487.9, 0.1
      assert_in_delta ClearSky.w_per_m2(5.0), 48.6, 0.1
    end
  end

  describe "SunPaths" do
    defp paths(opts \\ []) do
      location =
        Location.new(Keyword.get(opts, :zone, "Europe/Berlin"),
          lat: Keyword.get(opts, :lat, 52.52),
          lon: Keyword.get(opts, :lon, 13.405)
        )

      SunPaths.build(location, 2026)
    end

    defp peak(path), do: path.points |> Enum.map(&elem(&1, 1)) |> Enum.max()

    test "draws the solstices and the equinox, highest at midsummer" do
      [summer, equinox, winter] = paths()

      assert Enum.map([summer, equinox, winter], & &1.day) ==
               [:summer_solstice, :equinox, :winter_solstice]

      assert_in_delta peak(summer), 61.0, 1.0
      assert_in_delta peak(equinox), 37.5, 1.0
      assert_in_delta peak(winter), 14.0, 1.0
      assert Enum.map([summer, equinox, winter], &length(&1.points)) == [66, 48, 30]
    end

    test "marks every third clock hour the sun is up, in the given zone" do
      [summer, _equinox, winter] = paths()

      assert Enum.map(summer.dots, & &1.hour) === [6, 9, 12, 15, 18]
      assert Enum.map(winter.dots, & &1.hour) == [9, 12, 15]

      noon = paths(zone: "UTC") |> hd() |> Map.fetch!(:dots) |> Enum.find(&(&1.hour == 12))
      assert_in_delta noon.azimuth, 203.96, 0.5
      assert_in_delta noon.elevation, 59.27, 0.5
    end

    test "drops a date once the sun stays below the horizon, and everything without coordinates" do
      assert paths(lat: 66.0) |> List.last() |> Map.fetch!(:dots) |> Enum.map(& &1.hour) == [12]
      assert Enum.map(paths(lat: 67.0), & &1.day) == [:summer_solstice, :equinox]
      assert paths(lat: nil, lon: nil) == []
    end
  end
end
