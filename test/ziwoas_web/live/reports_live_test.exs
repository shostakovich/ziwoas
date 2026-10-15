defmodule ZiwoasWeb.ReportsLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.Energy.DailySummary
  alias Ziwoas.Plugs.DailyTotal
  alias Ziwoas.{Repo, TestClock, TestConfigs}
  alias Ziwoas.Weather.Record

  setup do
    TestClock.freeze("2026-04-10T12:00:00+02:00")
    :ok
  end

  defp total!(plug_id, date, energy_wh),
    do:
      Repo.insert!(%DailyTotal{
        plug_id: plug_id,
        date: Date.from_iso8601!(date),
        energy_wh: energy_wh * 1.0
      })

  defp page(conn, params \\ []),
    do: conn |> get(~p"/reports?#{params}") |> html_response(200) |> LazyHTML.from_document()

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()
  defp attr(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  defp squish(text), do: text |> String.split() |> Enum.join(" ")
  defp from(html), do: LazyHTML.from_fragment(html)

  defp payload(doc, chart),
    do: doc |> attr("#report_#{chart}-chart", "data-payload") |> hd() |> JSON.decode!()

  test "reports page renders", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn)

    assert texts(doc, "h1") == ["Berichte"]
    assert texts(doc, "header p") == ["04.04.–10.04.2026\u2060\u00A0· 7 Tage"]
    assert count(doc, "section[aria-label='Zeitraum']") == 1
    assert texts(doc, "title") == ["Berichte"]
    assert texts(doc, "#app-shell-nav a[aria-current=page]") == ["Berichte"]
    assert count(doc, "main#main.max-w-5xl") == 1
  end

  test "the date fields span the aggregated days, and a range starts no earlier", %{conn: conn} do
    total!("fridge", "2024-03-01", 100)
    total!("fridge", "2026-04-09", 100)

    doc = page(conn, start_date: "1026-04-01", end_date: "2026-04-07")

    assert attr(doc, "#start_date", "min") == ["2024-03-01"]
    assert attr(doc, "#end_date", "min") == ["2024-03-01"]
    assert attr(doc, "#start_date", "max") == ["2026-04-09"]
    assert attr(doc, "#end_date", "max") == ["2026-04-09"]
    assert count(doc, "#range_invalid") == 0

    {:ok, view, _html} = live(conn, ~p"/reports?start_date=1026-04-01&end_date=2026-04-07")
    assert :sys.get_state(view.pid).socket.assigns.report.start_date == ~D[2024-03-01]
  end

  test "reports page accepts custom range params", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn, start_date: "2026-04-01", end_date: "2026-04-07")

    assert count(doc, "input[name='start_date'][value='2026-04-01']") == 1
    assert count(doc, "input[name='end_date'][value='2026-04-07']") == 1
  end

  test "dates outside ISO 8601 are an invalid range; the fields echo what was asked", %{
    conn: conn
  } do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn, start_date: "20260401", end_date: "2026-W15-2")

    assert attr(doc, "#start_date", "value") == ["20260401"]
    assert attr(doc, "#end_date", "value") == ["2026-W15-2"]
    assert [warning] = texts(doc, "#range_invalid")
    assert warning =~ "ungültig"
  end

  test "the weather switches are toggles in their charts, off until switched on", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)

    Repo.insert!(%Record{
      kind: :historic,
      lat: 52.52,
      lon: 13.405,
      timestamp: ~U[2026-04-03 10:00:00.000000Z],
      daytime: "day",
      icon: "clear-day",
      solar: 0.5
    })

    path = ~p"/reports?start_date=2026-04-01&end_date=2026-04-07"
    doc = page(conn, start_date: "2026-04-01", end_date: "2026-04-07")

    assert texts(doc, "#report_daily form[phx-change=toggle_weather] label") == ["Wetter"]
    assert attr(doc, "#report-daily-weather[type=checkbox]", "data-weather-toggle") == ["daily"]
    assert count(doc, "#report-daily-weather[checked]") == 0
    refute "Einstrahlung (kWh/m²)" in texts(doc, "#report_daily ul li")

    {:ok, view, _html} = live(conn, path)
    daily = payload(from(render(view)), "daily")

    assert [nil, nil, %{"asset_name" => "weather_clear_day.webp", "alt" => "clear"} | _] =
             daily["weather"]["icons"]

    assert daily["weather_assets"] == %{
             "weather_clear_day.webp" => "/images/weather_clear_day.webp"
           }

    view |> element("#report_daily_weather") |> render_change(%{chart: "daily", visible: "true"})
    doc = from(render(view))

    assert count(doc, "#report-daily-weather[checked]") == 1
    assert "Einstrahlung (kWh/m²)" in texts(doc, "#report_daily ul li")
    assert count(doc, "#report-detail-weather[checked]") == 0

    doc = view |> render_patch(~p"/reports?start_date=2026-04-08&end_date=2026-04-10") |> from()

    assert count(doc, "#report-daily-weather") == 0
    refute "Einstrahlung (kWh/m²)" in texts(doc, "#report_daily ul li")
  end

  test "a custom range selects no preset", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn, start_date: "2026-04-01", end_date: "2026-04-07")

    assert count(doc, "nav#range_presets[aria-label='Schnellauswahl'] a") == 2
    assert count(doc, "nav#range_presets a[aria-current]") == 0
  end

  test "the active preset is marked as the current page", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn, preset: "last_30")

    assert texts(doc, "#range_presets a[aria-current='page']") == ["Letzte 30 Tage"]

    assert attr(doc, "#range_presets a", "href") == [
             "/reports?preset=last_7",
             "/reports?preset=last_30"
           ]

    assert attr(doc, "#range_presets a", "data-phx-link-state") == ["replace", "replace"]
  end

  test "the date form labels its fields and submits to the LiveView", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn)
    form = LazyHTML.query(doc, "form#range_form[phx-submit='apply_range']")

    assert texts(form, "label:has(#start_date) span, label[for='start_date']") |> hd() == "Von"
    assert count(form, "input#start_date[type='date']") == 1
    assert count(form, "input#end_date[type='date']") == 1
    assert texts(form, "button[type='submit']") == ["Anwenden"]
  end

  test "an invalid range is reported as a warning", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn, start_date: "2026-04-07", end_date: "2026-04-01")

    assert [warning] = texts(doc, "#range_invalid")
    assert warning =~ "ungültig"
  end

  test "summary tiles, the plugs' ranking and three charts loading until connected", %{
    conn: conn
  } do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn)

    assert texts(doc, "section[aria-label='Zusammenfassung'] .stat-title") == [
             "Ertrag",
             "Verbrauch",
             "Gespart",
             "Bilanz",
             "Autarkie",
             "Eigen­verbrauchs­quote",
             "Ø Ertrag je Tag",
             "Ø Verbrauch je Tag"
           ]

    assert texts(doc, "section[aria-label='Zusammenfassung'] .stat-desc") == ["ausgeglichen"]

    assert texts(doc, "main h2") == [
             "Steckdosen",
             "Energie",
             "Leistung",
             "Autarkie und Eigenverbrauchsquote"
           ]

    assert attr(doc, "section.card[aria-busy=true]", "id") ==
             ~w[report_daily report_detail report_ratios]

    assert count(doc, "[phx-hook=EnergyReport]") == 0
    assert count(doc, "main script") == 0
  end

  test "once connected each chart is an EnergyReport hook with its own payload", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    {:ok, view, _html} = live(conn, ~p"/reports")
    doc = from(render(view))

    assert attr(doc, "[phx-hook=EnergyReport]", "data-chart") == ~w[daily detail ratios]

    daily = payload(doc, "daily")
    assert hd(daily["labels"]) == "04.04."
    assert daily["produced_kwh"] == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    assert daily["weather_assets"] == %{}

    detail = payload(doc, "detail")
    assert detail["chart_type"] == "line"
    assert detail["consumer_order"] == ["fridge"]

    assert length(payload(doc, "ratios")["ratios"]) == 7
  end

  test "the ranking: producers and consumers as groups, consumers by place, shares in one tone",
       %{conn: conn} do
    TestConfigs.put(
      TestConfigs.plugs("""
        - id: washer
          name: Washer
          role: consumer
      """)
    )

    total!("bkw", "2026-04-10", 2000)
    total!("fridge", "2026-04-10", 500)
    total!("washer", "2026-04-10", 800)
    doc = page(conn)

    assert texts(doc, "tbody[id^=ranking-] th[scope=colgroup]") == ["Erzeugung", "Verbrauch"]

    assert attr(doc, "tbody#ranking-producers tr[data-plug-id]", "data-plug-id") == ["bkw"]

    assert attr(doc, "tbody#ranking-consumers tr[data-plug-id]", "data-plug-id") ==
             ~w[washer fridge]

    assert texts(doc, "tbody#ranking-consumers [data-role=place]") == ["1", "2"]
    assert count(doc, "tbody#ranking-producers [data-role=place]") == 0

    fridge = LazyHTML.query(doc, "tr#ranking-plug-fridge")
    assert texts(fridge, "td") == ["2", "Fridge 39 %", "0,50 kWh"]
    assert attr(fridge, "[data-role=share] progress", "aria-label") == ["Fridge"]
    assert count(doc, "[data-role=share][data-series]") == 0
  end

  test "the power chart names its resolution and range", %{conn: conn} do
    for i <- 0..29,
        do: total!("bkw", Date.to_iso8601(Date.add(~D[2026-04-01], i)), 2000)

    assert "Watt · Tagesmittel · 01.04.–30.04." in texts(
             page(conn, preset: "last_30"),
             "#report_detail .card-title + p"
           )
  end

  test "the power chart's range names the year only when it is not this one", %{conn: conn} do
    for i <- 0..2, do: total!("bkw", Date.to_iso8601(Date.add(~D[2026-04-01], i)), 2000)
    range = [start_date: "2026-04-01", end_date: "2026-04-03"]

    assert texts(page(conn, range), "#report_detail .card-title + p") == [
             "Watt · 5-Min-Werte · 01.04.–03.04."
           ]

    TestClock.freeze("2027-01-10T12:00:00+01:00")

    assert texts(page(conn, range), "#report_detail .card-title + p") == [
             "Watt · 5-Min-Werte · 01.04.2026–03.04.2026"
           ]
  end

  test "a range without any data shows zeros and says the plugs have none", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn, start_date: "2020-01-01", end_date: "2020-01-07")

    assert texts(doc, ".stat-value") |> hd() == "0,00 kWh"
    assert count(doc, "tbody[id^=ranking-]") == 0

    assert texts(doc, "#ranking_heading + * p.font-semibold, section p.font-semibold") |> hd() ==
             "Keine Steckdosendaten"
  end

  test "reports page shows an empty state without data", %{conn: conn} do
    doc = page(conn)

    assert texts(doc, "main h2") == ["Noch keine Berichtsdaten"]
    assert texts(doc, "main p") |> Enum.any?(&(&1 =~ "sobald die erste Tagesaggregation"))
    assert count(doc, "#range_form") == 0
  end

  test "the ratios chart and its table of days", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)

    Repo.insert!(%DailySummary{
      date: ~D[2026-04-10],
      produced_wh: 2000.0,
      consumed_wh: 1000.0,
      self_consumed_wh: 500.0
    })

    doc = page(conn)

    assert texts(doc, "#report_ratios .card-title") == ["Autarkie und Eigenverbrauchsquote"]
    assert texts(doc, "#report_ratios ul li") == ["Autarkie", "Eigenverbrauchsquote"]
    assert texts(doc, "tbody#report_ratios_data tr") |> List.last() == "10.04.2026 50,0 % 25,0 %"
    assert "50,0 %" in texts(doc, ".stat-value")
  end

  test "mounts connected, on the test's database", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    {:ok, view, _html} = live(conn, ~p"/reports?preset=last_30")
    doc = view |> render() |> LazyHTML.from_fragment()

    assert "Steckdosen" in texts(doc, "h2")
    assert attr(doc, "#range_presets a[aria-current=page]", "href") == ["/reports?preset=last_30"]
  end

  describe "connected" do
    setup do
      for i <- 0..29, do: total!("bkw", Date.to_iso8601(Date.add(~D[2026-03-12], i)), 2000)
      :ok
    end

    test "a preset link patches the page to its range", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reports")
      assert length(payload(from(render(view)), "daily")["labels"]) == 7

      view |> element("#range_presets a", "30 Tage") |> render_click()

      assert_patched(view, ~p"/reports?preset=last_30")
      doc = from(render(view))
      assert length(payload(doc, "daily")["labels"]) == 30

      assert attr(doc, "#range_presets a[aria-current=page]", "href") == [
               "/reports?preset=last_30"
             ]
    end

    test "the range form patches to the chosen dates", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reports")

      view
      |> form("#range_form", %{start_date: "2026-04-01", end_date: "2026-04-03"})
      |> render_submit()

      assert_patched(view, ~p"/reports?#{[end_date: "2026-04-03", start_date: "2026-04-01"]}")
      doc = from(render(view))
      assert payload(doc, "daily")["labels"] == ["01.04.", "02.04.", "03.04."]
      assert count(doc, "#range_presets a[aria-current]") == 0
      assert attr(doc, "#start_date", "value") == ["2026-04-01"]
    end

    test "an end date past the newest aggregate stops at it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reports?start_date=2026-04-08&end_date=2026-04-30")

      assert payload(from(render(view)), "daily")["labels"] == ["08.04.", "09.04.", "10.04."]
    end
  end
end
