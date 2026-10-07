defmodule ZiwoasWeb.SunChartComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Ziwoas.{Plot, Shading, SunCalendar}
  alias Ziwoas.Shading.{Bin, Curve, Dot, Panels, Profile, SkyMap}
  alias ZiwoasWeb.SunChartComponents

  defp html(fun, assigns), do: fun |> render_component(assigns) |> LazyHTML.from_fragment()
  defp query(doc, selector), do: LazyHTML.query(doc, selector)
  defp texts(doc, selector), do: doc |> query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))
  defp attrs(doc, selector, name), do: doc |> query(selector) |> LazyHTML.attribute(name)
  defp count(doc, selector), do: doc |> query(selector) |> Enum.count()
  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  describe "sun calendar" do
    defp day(date, opts \\ []) do
      %SunCalendar.Day{
        doy: Date.day_of_year(date),
        date: date,
        pv_kwh: opts[:pv_kwh],
        irradiance_kwh_per_m2: opts[:irradiance],
        cloud_avg: opts[:cloud]
      }
    end

    defp days(overrides \\ %{}) do
      for date <- Date.range(~D[2026-01-01], ~D[2026-12-31]),
          do: Map.get(overrides, Date.day_of_year(date), day(date))
    end

    defp calendar(opts) do
      days = Keyword.get(opts, :days, days())
      strip = &%SunCalendar.Strip{key: &1, title: &2, unit: &3, ramp: &4, max: &5, values: &6}

      %SunCalendar.Year{
        year: 2026,
        days: days,
        hours: {3, 22},
        strips: [
          strip.(
            :pv,
            "PV-Leistung",
            "W",
            :amber,
            Keyword.get(opts, :pv_max, 800.0),
            Keyword.get(opts, :pv, %{{100, 12} => 600.0})
          ),
          strip.(:irradiance, "Einstrahlung", "W/m²", :blue, 900.0, %{}),
          strip.(:cloud, "Bewölkung", "%", :grey, 100.0, %{})
        ],
        max_kwh:
          days |> Enum.map(& &1.pv_kwh) |> Enum.reject(&is_nil/1) |> Enum.max(fn -> nil end),
        lines: Keyword.get(opts, :lines, %SunCalendar.Lines{rise: [], set: [], noon: []}),
        seam: opts[:seam]
      }
    end

    defp render_calendar(opts \\ []),
      do: html(&SunChartComponents.sun_calendar/1, calendar: calendar(opts))

    test "stacks the three strips and the daily bars on one time axis" do
      doc = render_calendar()

      assert attrs(doc, "[data-strip]", "data-strip") == ~w[pv irradiance cloud energy]

      assert texts(doc, ".sun-calendar h3") == [
               "PV-Leistung",
               "Einstrahlung",
               "Bewölkung",
               "PV-Energie je Tag"
             ]
    end

    test "shows the empty state while no PV hour exists" do
      doc = render_calendar(pv: %{})

      assert texts(doc, ".empty-state h2") == ["Noch kein Sonnenkalender"]
      assert count(doc, "svg") == 0
    end

    test "paints cells by their share, merges equal neighbours and grounds only the empty hours" do
      doc = render_calendar(pv: %{{100, 12} => 800.0})

      assert attrs(doc, "[data-strip='pv'] .cells g[style]", "style") == [
               "fill: var(--ramp-amber-2)"
             ]

      assert count(doc, "[data-strip='pv'] .cells g.nodata") == 1
      assert attrs(doc, "[data-strip='pv'] .cells g.nodata", "style") == []
      assert count(doc, "[data-strip='pv'] .cells g.nodata rect") == 21
      assert count(doc, "[data-strip='irradiance'] .cells g.nodata rect") == 20

      merged = render_calendar(pv: Map.new(10..14, &{{&1, 12}, 400.0}))
      assert [width] = attrs(merged, "[data-strip='pv'] .cells g[style] rect", "width")
      assert_in_delta width |> Float.parse() |> elem(0), 5 * (720 - 60) / 365.0, 0.05
    end

    test "stretches the wide cells onto the phone's rows instead of writing them twice" do
      doc = render_calendar()

      assert attrs(doc, "[data-strip='pv'] svg.strip-chart-narrow use.cells", "transform") ==
               ["matrix(1 0 0 3.125 0 -63.8)"]

      assert attrs(doc, "[data-strip='pv'] svg.strip-chart-narrow use.cells", "href") == [
               "#sun-cells-pv"
             ]
    end

    test "marks the seam on the PV strip only, and explains both sources" do
      doc = render_calendar(seam: ~D[2026-06-20])

      assert attrs(doc, "[data-strip='pv'] svg.strip-chart-wide line.seam", "x1") == ["363.4"]
      assert attrs(doc, "[data-strip='pv'] svg.strip-chart-narrow line.seam", "y2") == ["530"]

      assert count(doc, "[data-strip='irradiance'] line.seam, [data-strip='energy'] line.seam") ==
               0

      assert hd(texts(doc, "[data-strip='pv'] .legend")) =~ "Wechsel der Quelle"
      [note] = texts(doc, ".sun-calendar .note")
      assert note =~ "Bis 19.06." and note =~ "ab 20.06." and note =~ "(AC)" and note =~ "(DC)"

      plain = render_calendar()
      assert count(plain, "line.seam") == 0
      assert count(plain, ".sun-calendar .note") == 0
    end

    test "draws the sun lines once per frame, lets the other strips reuse them, and breaks them at gaps" do
      days = Enum.to_list(1..100) ++ Enum.to_list(102..365)

      lines = %SunCalendar.Lines{
        rise: Enum.map(days, &{&1, 8.0}),
        set: Enum.map(days, &{&1, 16.0}),
        noon: Enum.map(days, &{&1, 12.0})
      }

      doc = render_calendar(lines: lines)

      assert attrs(doc, "g.sun-lines[id]", "id") == ["sun-lines-wide", "sun-lines-narrow"]

      assert attrs(doc, "[data-strip='cloud'] use.sun-lines", "href") == [
               "#sun-lines-wide",
               "#sun-lines-narrow"
             ]

      assert count(doc, "#sun-lines-wide polyline.sun.rise") == 2
      assert count(doc, "#sun-lines-wide polyline.sun-halo") == 6
      assert hd(texts(doc, "[data-strip='pv'] .legend")) =~ "Sonnenhöchststand"

      bare = render_calendar()
      assert count(bare, "polyline.sun") == 0
      refute hd(texts(bare, "[data-strip='pv'] .legend")) =~ "Sonnenaufgang"
    end

    test "gives every day a tooltip with its numbers, naming what is missing" do
      doc =
        render_calendar(
          days:
            days(%{
              100 => day(~D[2026-04-10], pv_kwh: 4.213, irradiance: 3.4, cloud: 48.6),
              101 => day(~D[2026-04-11], pv_kwh: 4.213)
            })
        )

      titles = texts(doc, "[data-strip='pv'] svg.strip-chart-wide .hits title")

      assert length(titles) == 365
      assert Enum.at(titles, 0) == "Do 01.01.2026 · keine Daten"

      assert Enum.at(titles, 99) ==
               "Fr 10.04.2026 · PV-Energie 4,21 kWh · Einstrahlung 3,40 kWh/m² · Bewölkung Ø 49 %"

      assert Enum.at(titles, 100) ==
               "Sa 11.04.2026 · PV-Energie 4,21 kWh · Einstrahlung keine Daten · Bewölkung keine Daten"

      assert count(doc, "svg.strip-chart-narrow .hits, svg.energy-chart-narrow .hits") == 0
    end

    test "outlines neighbouring days as one area and breaks it at a day without energy" do
      one =
        render_calendar(
          days:
            days(%{
              100 => day(~D[2026-04-10], pv_kwh: 4.0),
              101 => day(~D[2026-04-11], pv_kwh: 2.0)
            })
        )

      assert attrs(one, "svg.energy-chart-wide .bars path", "d") == [
               "M235 130V30H236.8V80H238.6V130Z"
             ]

      two =
        render_calendar(
          days:
            days(%{
              100 => day(~D[2026-04-10], pv_kwh: 4.0),
              102 => day(~D[2026-04-12], pv_kwh: 0.0)
            })
        )

      assert ["M235 130V30H236.8V130Z", "M238.6 130V130H240.4V130Z"] =
               attrs(two, "svg.energy-chart-wide .bars path", "d")
    end

    test "puts the maximum and the unit into every strip's legend, with a thousands dot" do
      assert texts(render_calendar(pv_max: 1200.0), "[data-strip='pv'] .legend-item") |> hd() ==
               "01.200 W"

      assert length(texts(render_calendar(), ".sun-calendar .legend")) == 3
    end
  end

  describe "yield map" do
    defp bin(opts \\ []) do
      %Bin{
        azimuth: Keyword.get(opts, :azimuth, 140),
        elevation: Keyword.get(opts, :elevation, 45),
        share: Keyword.get(opts, :share, 0.8),
        hours: 12,
        first_hour: 11,
        last_hour: 13
      }
    end

    defp sun_path(dots \\ []),
      do: %Shading.Path{
        label: "21.6.",
        points: [{60.0, 5.0}, {180.0, 60.0}, {300.0, 4.0}],
        dots: dots
      }

    defp render_map(bins, paths \\ [sun_path()]),
      do:
        html(&SunChartComponents.yield_map/1, map: %SkyMap{bins: bins, paths: paths, bin_size: 5})

    test "draws one field per bin, titled where a pointer can ask" do
      doc = render_map([bin(), bin(azimuth: 200, elevation: 30, share: 1.4)])

      assert count(doc, "svg.yield-map-wide .fields rect") == 2
      assert count(doc, "svg.yield-map-narrow .fields rect") == 2
      assert count(doc, "svg.yield-map-narrow .fields title") == 0

      assert texts(doc, "svg.yield-map-wide .fields title") |> hd() ==
               "Azimut 140–145° · Höhe 45–50° · Ausbeute 80 % · 12 Stunden · 11–13 Uhr"

      assert "fill: var(--ramp-high)" in attrs(doc, "svg.yield-map-wide .fields > g", "style")
    end

    test "names the compass on both densities and the degrees only on the wide sky" do
      doc = render_map([bin()])

      assert texts(doc, "svg.yield-map-wide .month-labels text") ==
               ["60°", "Ost 90°", "120°", "150°", "Süd 180°", "210°", "240°", "West 270°", "300°"]

      assert texts(doc, "svg.yield-map-narrow .month-labels text") == ["Ost", "Süd", "West"]
      assert texts(doc, "svg.yield-map-narrow .hour-labels text") == ["0°", "20°", "40°", "60°"]
    end

    test "names every marked hour on the wide sky and only noon, over its dot, on the phone's" do
      dots = [
        %Dot{hour: 9, azimuth: 120.0, elevation: 40.0},
        %Dot{hour: 12, azimuth: 195.0, elevation: 58.0},
        %Dot{hour: 15, azimuth: 240.0, elevation: 40.0}
      ]

      doc = render_map([bin()], [sun_path(dots)])

      assert texts(doc, "svg.yield-map-wide text.dot-label") == ["09:00", "12:00", "15:00"]
      assert count(doc, "svg.yield-map-narrow circle.dot") == 3
      assert texts(doc, "svg.yield-map-narrow text.dot-label") == ["12:00"]

      noon = query(doc, "svg.yield-map-narrow text.dot-label")
      [cx] = attrs(doc, "svg.yield-map-narrow circle.dot:nth-of-type(2)", "cx")
      assert LazyHTML.attribute(noon, "text-anchor") == ["start"]

      assert LazyHTML.attribute(noon, "x") == [
               Plot.to_s(Plot.number(elem(Float.parse(cx), 0) + 10))
             ]
    end

    test "hangs the date under the lowest arc and over the others" do
      low = %Shading.Path{
        label: "21.12.",
        points: [{130.0, 2.0}, {180.0, 14.0}, {230.0, 2.0}],
        dots: []
      }

      doc = render_map([bin()], [sun_path(), low])

      assert attrs(doc, "svg.yield-map-wide text.path-label", "dominant-baseline") == [
               "auto",
               "hanging"
             ]

      assert attrs(doc, "svg.yield-map-narrow text.path-label", "text-anchor") == [
               "start",
               "middle"
             ]
    end

    test "waits for the first fields with a word instead of an empty sky" do
      doc = render_map([])

      assert count(doc, "svg") == 0
      assert hd(texts(doc, "p.note")) =~ "Die Karte füllt sich"
    end
  end

  describe "daily profiles" do
    defp profile(month, days, measured \\ [{10, 300.0}, {11, 400.0}, {12, 500.0}]) do
      %Profile{
        month: month,
        days: days,
        curves: [
          %Curve{key: :measured, points: measured},
          %Curve{key: :expected, points: [{10, 350.0}, {11, 450.0}, {12, 600.0}]},
          %Curve{key: :theory, points: [{10, 500.0}, {11, 600.0}, {12, 700.0}]}
        ]
      }
    end

    defp render_profiles(profiles),
      do: html(&SunChartComponents.daily_profiles/1, profiles: profiles)

    test "gives every month its own picture, named, counted, the unfinished ones quieter" do
      doc = render_profiles([profile(6, 30), profile(7, 1), profile(2, 28)])

      assert texts(doc, "figcaption") == ["Jun 30 Tage", "Jul 1 Tag", "Feb 28 Tage"]
      assert attrs(doc, ".multiple.partial", "data-month") == ["7"]
      assert attrs(doc, ".multiple[data-month='7'] svg", "class") == ["opacity-50"]
      assert attrs(doc, ".multiple[data-month='6'] svg", "class") == []
      assert texts(doc, ".card-subtitle") == ["Mittlere Leistung je Stunde in W"]

      assert texts(doc, ".legend-item") == [
               "PV gemessen",
               "Erwartet aus Einstrahlung",
               "Wolkenloser Himmel"
             ]
    end

    test "draws the measured line last, breaks curves and fills at a missing hour" do
      doc = render_profiles([profile(6, 30, [{10, 300.0}, {12, 500.0}])])

      assert attrs(doc, "polyline.curve", "class") == [
               "curve theory",
               "curve expected",
               "curve measured",
               "curve measured"
             ]

      assert count(doc, "polygon.measured-area") == 2
    end

    test "tells every hour's three numbers" do
      doc = render_profiles([profile(6, 30, [{10, 1234.4}])])

      assert texts(doc, ".hits title") == [
               "Jun · 10–11 Uhr · PV gemessen Ø 1.234 W · Erwartet aus Einstrahlung Ø 350 W · Wolkenloser Himmel Ø 500 W",
               "Jun · 11–12 Uhr · PV gemessen keine Daten · Erwartet aus Einstrahlung Ø 450 W · Wolkenloser Himmel Ø 600 W",
               "Jun · 12–13 Uhr · PV gemessen keine Daten · Erwartet aus Einstrahlung Ø 600 W · Wolkenloser Himmel Ø 700 W"
             ]
    end

    test "waits for the first month with a word" do
      doc = render_profiles([])

      assert texts(doc, ".card-subtitle") == []
      assert hd(texts(doc, "p.note")) =~ "sobald ein Monat Stundenwerte hat"
    end
  end

  describe "panel curves" do
    defp panels(curves, days \\ 16, since \\ ~D[2026-08-27]),
      do: %Panels{
        curves: Enum.map(curves, fn {key, points} -> %Curve{key: key, points: points} end),
        days: days,
        since: since
      }

    defp four(overrides \\ []) do
      Keyword.merge(
        [
          pv1: [{12, 300.0}, {13, 400.0}, {14, 350.0}],
          pv2: [{12, 280.0}, {13, 380.0}, {14, 330.0}],
          pv3: [{12, 120.0}, {13, 160.0}, {14, 150.0}],
          pv4: [{12, 100.0}, {13, 140.0}, {14, 130.0}]
        ],
        overrides
      )
    end

    defp render_panels(panels), do: html(&SunChartComponents.panel_curves/1, panels: panels)
    defp label_ys(doc), do: attrs(doc, "svg.panel-chart-wide .direct-labels text", "y")

    test "says since when the days were counted, in the singular for one" do
      assert texts(render_panels(panels(four())), ".card-subtitle") == [
               "seit 27.08.2026 · 16 Tage"
             ]

      assert texts(render_panels(panels(four(), 1)), ".card-subtitle") == [
               "seit 27.08.2026 · 1 Tag"
             ]
    end

    test "names the lines in the wide drawing only, the legend on the phone" do
      doc = render_panels(panels(four()))

      assert texts(doc, "svg.panel-chart-wide .direct-labels text") == [
               "Panel 1",
               "Panel 2",
               "Panel 3",
               "Panel 4"
             ]

      assert count(doc, "svg.panel-chart-narrow .direct-labels") == 0
      assert texts(doc, "ul.legend.d-sm-none li") == ["Panel 1", "Panel 2", "Panel 3", "Panel 4"]
      assert count(doc, "svg.panel-chart-narrow .hits") == 0
    end

    test "lifts the names back over the axis when pushing them apart ran out of room" do
      flat = four(pv1: [{12, 5.0}], pv2: [{12, 4.0}], pv3: [{12, 3.0}], pv4: [{12, 2.0}])
      assert label_ys(render_panels(panels(flat))) == ~w[122 142 162 182]

      single = fn watts -> panels(pv1: [{13, watts}], pv2: [], pv3: [], pv4: []) end
      assert label_ys(render_panels(single.(0.0))) == ["182"]
      assert label_ys(render_panels(single.(1.3))) == ["182"]
      assert label_ys(render_panels(single.(1.4))) == ["181.9"]
    end

    test "sorts the names by height before spreading them, skipping a panel without reading" do
      scattered = panels(pv1: [{13, 50.0}], pv2: [{13, 750.0}], pv3: [{13, 400.0}], pv4: [])

      assert attrs(render_panels(scattered), "svg.panel-chart-wide .direct-labels text", "class") ==
               ~w[pv2 pv3 pv1]
    end

    test "tells all four numbers of an hour, and says so where one has none" do
      doc = render_panels(panels(four(pv4: [{12, 1234.0}])))

      assert texts(doc, "svg.panel-chart-wide .hits title") |> Enum.at(1) ==
               "13–14 Uhr · Panel 1 Ø 400 W · Panel 2 Ø 380 W · Panel 3 Ø 160 W · Panel 4 keine Daten"

      assert texts(doc, "svg.panel-chart-wide .hits title") |> hd() =~ "Panel 4 Ø 1.234 W"
    end

    test "waits for the first full day with a word, naming no period" do
      doc = render_panels(panels([pv1: [], pv2: [], pv3: [], pv4: []], 0, nil))

      assert count(doc, "svg") == 0
      assert texts(doc, ".card-subtitle") == []
      assert hd(texts(doc, "p.note")) =~ "sobald alle vier Panels einen Tag lang geliefert haben"
    end
  end

  test "the shading report waits for its first hours as a whole" do
    report = %Shading.Report{
      map: %SkyMap{bins: [], paths: [], bin_size: 5},
      profiles: [],
      panels: %Panels{curves: [], days: 0}
    }

    doc = html(&SunChartComponents.shading/1, report: report)

    assert texts(doc, ".empty-state h2") == ["Noch keine Ausbeute"]
  end
end
