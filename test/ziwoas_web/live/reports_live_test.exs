defmodule ZiwoasWeb.ReportsLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.EnergyReport.DailyEnergySummary
  alias Ziwoas.Plugs.DailyTotal
  alias Ziwoas.{Repo, TestClock}
  alias Ziwoas.Weather.Record

  setup do
    TestClock.freeze("2026-04-10T12:00:00+02:00")
    :ok
  end

  defp total!(plug_id, date, energy_wh),
    do: Repo.insert!(%DailyTotal{plug_id: plug_id, date: date, energy_wh: energy_wh * 1.0})

  defp page(conn, params \\ []),
    do: conn |> get(~p"/reports?#{params}") |> html_response(200) |> LazyHTML.from_document()

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()
  defp attr(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  test "reports page renders", %{conn: conn} do
    doc = page(conn)

    assert texts(doc, "h1") == ["Berichte"]
    assert count(doc, "section[aria-label='Zeitraum']") == 1
    assert texts(doc, "title") == ["Berichte"]
    assert texts(doc, "nav[aria-label=Hauptnavigation] a.active") == ["Berichte"]
    assert count(doc, "main.app-main-wide") == 1
  end

  test "reports page accepts custom range params", %{conn: conn} do
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
    assert [warning] = texts(doc, ".alert.alert-warning")
    assert warning =~ "ungültig"
  end

  test "the weather switch says what it does", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)

    Repo.insert!(%Record{
      kind: "historic",
      lat: 52.52,
      lon: 13.405,
      timestamp: ~U[2026-04-03 10:00:00.000000Z],
      daytime: "day",
      icon: "clear-day",
      solar: 0.5
    })

    doc = page(conn, start_date: "2026-04-01", end_date: "2026-04-07")

    assert texts(doc, "label[for='report-daily-weather']") == ["Wetter einblenden"]

    assert attr(doc, "#report-daily-weather[phx-update=ignore]", "data-weather-toggle") == [
             "daily"
           ]

    assert count(doc, "#energy_report script[data-island='weather-assets']") == 1
  end

  test "a custom range marks Benutzerdefiniert, not a preset, as active", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn, start_date: "2026-04-01", end_date: "2026-04-07")

    assert texts(doc, ".btn-group[aria-label='Schnellauswahl'] .btn.active") == [
             "Benutzerdefiniert"
           ]

    assert count(doc, ".btn-group[aria-label='Schnellauswahl'] a[aria-current]") == 0
  end

  test "the active preset is marked as the current page", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn, preset: "last_30")

    assert count(doc, ".btn-group[aria-label='Schnellauswahl'] a.btn") == 2

    assert texts(doc, ".btn-group[aria-label='Schnellauswahl'] a.btn.active[aria-current='page']") ==
             ["Letzte 30 Tage"]

    assert count(doc, ".btn-group[aria-label='Schnellauswahl'] .btn.active") == 1

    assert attr(doc, ".btn-group a", "href") == [
             "/reports?preset=last_7",
             "/reports?preset=last_30"
           ]
  end

  test "the date form labels its fields and submits to the LiveView", %{conn: conn} do
    doc = page(conn)
    form = LazyHTML.query(doc, "form#range_form[phx-submit='apply_range']")

    assert texts(form, "label.form-label[for='start_date']") == ["Von"]
    assert texts(form, "label.form-label[for='end_date']") == ["Bis"]
    assert count(form, "input.form-control#start_date[type='date']") == 1
    assert count(form, "input.form-control#end_date[type='date']") == 1
    assert texts(form, "button[type='submit']:not([name])") == ["Anwenden"]
  end

  test "an invalid range is reported as a warning", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn, start_date: "2026-04-07", end_date: "2026-04-01")

    assert [warning] = texts(doc, ".alert.alert-warning")
    assert warning =~ "ungültig"
  end

  test "reports page renders summary ranking and chart payload", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn)

    assert count(doc, "section[aria-label='Zusammenfassung'] .stat") == 8

    assert texts(doc, "section[aria-label='Zusammenfassung'] .stat-label") == [
             "Ertrag",
             "Verbrauch",
             "Gespart",
             "Bilanz",
             "Autarkie",
             "Eigen­verbrauchs­quote",
             "Ø Ertrag/Tag",
             "Ø Verbrauch/Tag"
           ]

    headings = texts(doc, "main h2")
    refute "Zeitraum" in headings
    refute "Zusammenfassung" in headings
    assert "Steckdosen" in headings
    assert "kWh je Tag · Ertrag und Verbrauch" in texts(doc, ".card-subtitle")
    assert "Leistung" in texts(doc, ".card-title")
    assert count(doc, ".card .chart-frame") >= 2
    assert count(doc, "ul.list-group[aria-label='Erzeugung'] > li.list-group-item") == 1
    assert count(doc, "#energy_report[phx-hook=EnergyReport]") == 1

    assert attr(doc, "#energy_report [phx-update=ignore][id] > canvas", "data-chart") ==
             ~w[daily detail ratios]

    assert count(doc, "#energy_report script[data-island='payload']") == 1
  end

  test "the payload island is JSON the script tag cannot end early", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    body = conn |> get(~p"/reports") |> html_response(200)

    assert [_, json] = Regex.run(~r{data-island="payload">(.*?)</script>}s, body)

    payload = JSON.decode!(json)
    assert hd(payload["daily"]["labels"]) == "04.04."
    assert payload["daily"]["produced_kwh"] == [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    assert payload["detail"]["chart_type"] == "line"
    refute json =~ "<"
  end

  test "the producer stands apart from the numbered consumers, each bar in its dashboard colour",
       %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    total!("fridge", "2026-04-10", 500)
    doc = page(conn)

    producer =
      LazyHTML.query(doc, "ul.list-group[aria-label='Erzeugung'] > li[data-plug-id='bkw']")

    assert count(producer, "img[alt='Erzeuger']") == 1

    assert attr(producer, ".progress-bar", "style") == [
             "width: 100.0%; background-color: var(--viz-solar)"
           ]

    assert count(doc, "ol.list-group[aria-label='Rangliste'] > li") == 1

    consumer =
      LazyHTML.query(doc, "ol.list-group[aria-label='Rangliste'] > li[data-plug-id='fridge']")

    assert texts(consumer, ".col-1") == ["1"]

    assert attr(consumer, ".progress-bar", "style") == [
             "width: 25.0%; background-color: var(--viz-1)"
           ]

    assert texts(consumer, ".text-end") == ["0,50 kWh"]
    assert count(consumer, ".order-last.order-sm-0 > .progress") == 1
  end

  test "reports page orders widgets like the dashboard", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)

    assert ["Steckdosen", "Energie", "Leistung", "Autarkie & Eigenverbrauchsquote"] =
             texts(page(conn), "main h2")
  end

  test "reports page describes the power chart resolution", %{conn: conn} do
    for i <- 0..29,
        do: total!("bkw", Date.to_iso8601(Date.add(~D[2026-04-01], i)), 2000)

    assert "Watt · Tagesmittel · 01.04.–30.04." in texts(
             page(conn, preset: "last_30"),
             ".card-subtitle"
           )
  end

  test "the power chart's range names the year only when it is not this one", %{conn: conn} do
    for i <- 0..2, do: total!("bkw", Date.to_iso8601(Date.add(~D[2026-04-01], i)), 2000)
    range = [start_date: "2026-04-01", end_date: "2026-04-03"]

    assert "Watt · 5-Min-Werte · 01.04.–03.04." in texts(page(conn, range), ".card-subtitle")

    TestClock.freeze("2027-01-10T12:00:00+01:00")

    assert "Watt · 5-Min-Werte · 01.04.2026–03.04.2026" in texts(
             page(conn, range),
             ".card-subtitle"
           )
  end

  test "a range without any data shows zeros and no ranking", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    doc = page(conn, start_date: "2020-01-01", end_date: "2020-01-07")

    assert texts(doc, ".stat-value") |> hd() == "0,00 kWh"
    assert texts(doc, "p.small.text-body-secondary") == ["Keine Daten"]
  end

  test "reports page shows empty state without data", %{conn: conn} do
    doc = page(conn)

    assert texts(doc, ".card .card-title") == ["Noch keine Berichtsdaten"]
    assert hd(texts(doc, ".card p")) =~ "sobald die erste Tagesaggregation vorhanden ist"
    assert attr(doc, "#start_date", "value") == ["2026-04-10"]
  end

  test "reports page renders Autarkie & Eigenverbrauchsquote section", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)

    Repo.insert!(%DailyEnergySummary{
      date: "2026-04-10",
      produced_wh: 2000.0,
      consumed_wh: 1000.0,
      self_consumed_wh: 500.0
    })

    doc = page(conn)

    assert "Autarkie & Eigenverbrauchsquote" in texts(doc, ".card-title")
    assert count(doc, "#report_ratios_chart[phx-update=ignore] > canvas[data-chart=ratios]") == 1
    assert "50,0 %" in texts(doc, ".stat-value")
  end

  test "mounts connected, on the test's database", %{conn: conn} do
    total!("bkw", "2026-04-10", 2000)
    {:ok, view, _html} = live(conn, ~p"/reports?preset=last_30")
    doc = view |> render() |> LazyHTML.from_fragment()

    assert "Steckdosen" in texts(doc, "h2")
    assert attr(doc, ".btn-group a[aria-current=page]", "href") == ["/reports?preset=last_30"]
  end

  describe "connected" do
    setup do
      for i <- 0..29, do: total!("bkw", Date.to_iso8601(Date.add(~D[2026-03-12], i)), 2000)
      :ok
    end

    defp island(view) do
      [_, json] = Regex.run(~r{data-island="payload">(.*?)</script>}s, render(view))
      JSON.decode!(json)
    end

    test "a preset link patches the page to its range", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reports")
      assert length(island(view)["daily"]["labels"]) == 7

      view |> element(".btn-group a", "30 Tage") |> render_click()

      assert_patched(view, ~p"/reports?preset=last_30")
      assert length(island(view)["daily"]["labels"]) == 30

      assert attr(LazyHTML.from_fragment(render(view)), ".btn-group a[aria-current=page]", "href") ==
               [
                 "/reports?preset=last_30"
               ]
    end

    test "the range form patches to the chosen dates", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reports")

      view
      |> form("#range_form", %{start_date: "2026-04-01", end_date: "2026-04-03"})
      |> render_submit()

      assert_patched(view, ~p"/reports?#{[end_date: "2026-04-03", start_date: "2026-04-01"]}")
      assert island(view)["daily"]["labels"] == ["01.04.", "02.04.", "03.04."]

      doc = LazyHTML.from_fragment(render(view))
      assert texts(doc, ".btn-group .btn.active") == ["Benutzerdefiniert"]
      assert attr(doc, "#start_date", "value") == ["2026-04-01"]
    end

    test "an end date past the newest aggregate stops at it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reports?start_date=2026-04-08&end_date=2026-04-30")

      assert island(view)["daily"]["labels"] == ["08.04.", "09.04.", "10.04."]
    end
  end
end
