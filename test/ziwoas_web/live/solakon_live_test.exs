defmodule ZiwoasWeb.SolakonLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Repo, TestClock}
  alias Ziwoas.Economics.CostItem
  alias Ziwoas.Energy.DailySummary
  alias Ziwoas.Plugs.Sample5min
  alias Ziwoas.Solakon.{PvHour, Reading, Snapshot}
  alias Ziwoas.Weather.Record

  @now "2026-10-05T12:00:00+02:00"

  setup do
    TestClock.freeze(@now)
    :ok
  end

  defp now, do: Clock.parse!(@now)

  defp at(date, hour),
    do:
      date
      |> DateTime.new!(Time.new!(hour, 0, 0), "Europe/Berlin")
      |> usec()

  defp page(conn, path \\ ~p"/solakon"),
    do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

  defp loaded_page(conn) do
    {:ok, view, _html} = live(conn, ~p"/solakon")
    view |> render_async() |> LazyHTML.from_fragment()
  end

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp attrs(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()
  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  defp floats(schema, attrs),
    do:
      Map.new(attrs, fn {key, value} ->
        if is_integer(value) and schema.__schema__(:type, key) == :float,
          do: {key, value * 1.0},
          else: {key, value}
      end)

  defp snapshot!(attrs),
    do: Repo.insert!(struct!(%Snapshot{taken_at: now()}, floats(Snapshot, attrs)))

  defp reading!(attrs),
    do:
      Repo.insert!(
        struct!(
          %Reading{
            taken_at: now(),
            active_power_w: 0.0,
            pv_power_w: 0.0,
            battery_power_w: 0.0,
            battery_soc_pct: 50
          },
          floats(Reading, attrs)
        )
      )

  defp pv_hour!(date, hour, watts),
    do:
      Repo.insert!(%PvHour{
        started_at: at(date, hour),
        pv_power_w: watts,
        reading_count: 120,
        pv1_power_w: 100.0,
        pv2_power_w: 100.0,
        pv3_power_w: 100.0,
        pv4_power_w: 100.0
      })

  test "the page renders the single continuous Solakon overview", %{conn: conn} do
    doc = page(conn)

    assert texts(doc, "title") == ["PV"]
    assert texts(doc, "h1") == ["PV"]
    assert texts(doc, "nav[aria-label=Hauptnavigation] a.active") == ["PV"]
    assert count(doc, "main.app-main-wide") == 1
    assert attrs(doc, "#live_freshness[phx-hook=LiveFreshness]", "data-beat") == ["0"]
    assert count(doc, "#live_freshness #energy_flow[phx-hook=EnergyFlow][data-state]") == 1
    assert count(doc, "#energy_flow svg#energy_flow_svg[phx-update=ignore]") == 1

    for title <- ["Energiefluss", "Status", "Solakon-Verlauf", "Wirtschaftlichkeit"],
        do: assert(title in texts(doc, ".card-title"))

    assert texts(doc, "main h2.h6") |> Enum.take(3) == ["Steuerung", "Panels", "Speicher"]
    assert attrs(doc, "#solakon_history[phx-hook=SolakonHistory]", "data-range") == ["24h"]
    assert count(doc, "#solakon_history #solakon_history_frame[phx-update=ignore] > canvas") == 1
    assert count(doc, "#solakon_history script") == 0
    assert texts(doc, "#solakon_history a.btn.active") == ["Letzte 24 h"]

    assert count(doc, "button#solakon-eps-toggle[role=switch][phx-click=toggle_eps]") == 1
    assert count(doc, "button#solakon-control-toggle[role=switch][phx-click=toggle_control]") == 1
    assert count(doc, "label[for=solakon-eps-toggle]") == 1

    assert count(doc, "[data-async=loading]") == 3

    refute LazyHTML.text(doc) =~ ~r/SOH|EPS|46613|39067|Modbus/
    assert count(doc, ".ef-ring[data-ring='pv'] > img.icon[src*='icon_sonne'][alt='PV']") == 1
  end

  test "without an inverter configured the auto-regulation is off and cannot be switched", %{
    conn: conn
  } do
    doc = page(conn)

    assert texts(doc, ".stat-value#solakon-control-state") == ["Aus"]
    assert texts(doc, "#solakon-control-help") == ["in Konfiguration deaktiviert"]
    assert count(doc, "button#solakon-control-toggle[disabled][aria-checked=false]") == 1
  end

  test "switching the outlet without an inverter configured says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/solakon")

    view |> element("#solakon-eps-toggle") |> render_click()

    assert has_element?(view, "#solakon-eps-error:not([hidden])", "Solakon nicht konfiguriert")
    assert has_element?(view, "button#solakon-eps-toggle[aria-checked=false]:not([disabled])")
  end

  test "controls, panels, storage, balance and status without protocol language", %{conn: conn} do
    snapshot!(
      pv1_power_w: 210.6,
      pv1_voltage_v: 41.7,
      pv1_current_a: 5.12,
      pv2_power_w: 198,
      pv2_voltage_v: 40.5,
      pv2_current_a: 4.88,
      pv3_power_w: 176,
      pv4_power_w: 0,
      battery_health_pct: 97,
      battery_voltage_v: 51.3,
      battery_current_a: 4.2,
      battery_temperature_c: 24.8,
      full_charge_capacity_ah: 51.2,
      inverter_temperature_c: 34.1,
      eps_enabled: true,
      eps_voltage_v: 230.1,
      eps_power_w: 125
    )

    doc = page(conn)

    assert count(doc, ".solakon-control-card") == 2

    assert texts(doc, ".solakon-panel-grid .card") ==
             [
               "Panel 1 211 W 41,7 V · 5,12 A",
               "Panel 2 198 W 40,5 V · 4,88 A",
               "Panel 3 176 W 0,0 V · 0,00 A",
               "Panel 4 0 W 0,0 V · 0,00 A"
             ]

    assert texts(doc, ".solakon-details p") |> Enum.take(2) == [
             "Speichertemperatur (Status/Regelung) 24,8 °C",
             "Wechselrichtertemperatur 34,1 °C"
           ]

    assert texts(doc, ".solakon-storage-grid .stat-label") == [
             "Ladestand",
             "Batterie­gesundheit",
             "Aktuelle Batterie­leistung",
             "Batterie­spannung",
             "Batteriestrom",
             "Speicher­temperatur",
             "Volle Kapazität"
           ]

    assert texts(doc, ".solakon-storage-grid .stat-value") ==
             ["— %", "97 %", "— W", "51,3 V", "4,20 A", "24,8 °C", "51,2 Ah"]

    assert count(doc, ".solakon-balance-row") == 5
    # The visible text, not the markup: random tokens (CSRF, session) may contain „EPS“.
    refute LazyHTML.text(doc) =~ ~r/SOH|EPS|Modbus|Register|39067|46613|Fault\d|Alarm \d/
  end

  test "status shows the newest reading's battery character with a short description", %{
    conn: conn
  } do
    reading!(taken_at: DateTime.add(now(), -3600), battery_soc_pct: 50)

    reading!(
      battery_power_w: 80,
      battery_soc_pct: 84,
      battery_temperature_c: 24.8,
      eps_power_w: 0,
      eps_enabled: true
    )

    doc = page(conn)

    assert attrs(doc, ".solakon-status-figure img", "data-solakon-battery-state") == ["charging"]
    assert count(doc, ".solakon-status-figure img[src*=solakon_battery_charging]") == 1
    assert texts(doc, ".solakon-status-summary") == ["Akku lädt gerade"]
    assert "84 %" in texts(doc, ".solakon-storage-grid .stat-value")
    assert texts(doc, "#solakon-eps-state") == ["An"]
    assert count(doc, "button#solakon-eps-toggle[aria-checked=true]") == 1
  end

  test "the battery character: fault, warm, cold, low, discharging, quiet", %{conn: conn} do
    for {attrs, state, summary} <- [
          {[alarm2: 8], "fault", "Akku meldet Aufmerksamkeit"},
          {[battery_temperature_c: 45.0], "hot", "Akku ist warm"},
          {[battery_temperature_c: 5.0], "cold", "Akku ist kalt"},
          {[battery_soc_pct: 20], "low", "Akku ist niedrig geladen"},
          {[battery_power_w: -11], "normal", "Akku versorgt gerade das Haus"},
          {[battery_power_w: 10], "normal", "Alles ruhig am Speicher"}
        ] do
      Repo.delete_all(Reading)
      reading!(attrs)
      doc = page(conn)

      assert attrs(doc, ".solakon-status-figure img", "data-solakon-battery-state") == [state]
      assert texts(doc, ".solakon-status-summary") == [summary]
    end
  end

  test "the Wirtschaftlichkeit card sits between the history and the sun calendar", %{conn: conn} do
    assert loaded_page(conn) |> texts("a.btn") |> Enum.member?("Kosten erfassen")

    Repo.insert!(%CostItem{
      label: "Anlage",
      amount_eur: Decimal.new("1000.00"),
      spent_on: ~D[2026-01-01]
    })

    insert_price!("2026-01-01", "0.30")

    Repo.insert!(%DailySummary{
      date: ~D[2026-01-01],
      produced_wh: 5_000.0,
      consumed_wh: 3_000.0,
      self_consumed_wh: 2_000.0
    })

    doc = loaded_page(conn)
    html = LazyHTML.to_html(doc)

    assert hd(texts(doc, ".economics-tiles .stat-value")) == "1.000,00 €"
    assert Enum.at(texts(doc, ".economics-tiles .stat-value"), 1) == "0,60 €"
    assert attrs(doc, "a.btn-outline-secondary", "href") == ["/solakon/wirtschaftlichkeit"]
    {solakon, _} = :binary.match(html, "Solakon-Verlauf")
    {economics, _} = :binary.match(html, "Wirtschaftlichkeit")
    {calendar, _} = :binary.match(html, "Sonnenkalender")
    assert solakon < economics and economics < calendar
  end

  test "the shading section and the sun calendar, and their empty states", %{conn: conn} do
    empty = loaded_page(conn)
    assert count(empty, ".shading") == 0
    assert texts(empty, ".empty-state h2") == ["Noch kein Sonnenkalender", "Noch keine Ausbeute"]

    for index <- 0..2 do
      date = Date.add(~D[2026-07-01], index)
      pv_hour!(date, 12, 400.0)

      Repo.insert!(%Record{
        kind: :historic,
        daytime: "day",
        lat: 52.52,
        lon: 13.405,
        timestamp: at(date, 13),
        solar: 0.5
      })
    end

    Repo.insert!(%Sample5min{
      plug_id: "bkw",
      bucket_ts: DateTime.to_unix(at(~D[2026-03-01], 12)),
      avg_power_w: 120.0,
      energy_delta_wh: 10.0,
      sample_count: 12
    })

    doc = loaded_page(conn)

    assert "Sonnenkalender 2026" in texts(doc, "h2")
    assert count(doc, ".sun-calendar [data-strip]") == 4
    assert count(doc, ".sun-calendar [data-strip='pv'] svg.strip-chart-wide polyline.sun") == 3
    assert "Wechsel der Quelle" in texts(doc, ".sun-calendar .legend-item")
    assert count(doc, ".sun-calendar .note") == 1
    assert count(doc, ".shading [data-chart='yield-map'] .fields rect") >= 1
    assert count(doc, ".shading [data-chart='daily-profiles'] .multiple") == 1
    assert count(doc, ".shading [data-chart='panels'] .panel-chart-wide polyline") == 4
    assert texts(doc, "[data-chart='panels'] .card-subtitle") == ["seit 01.07.2026 · 3 Tage"]
  end

  describe "the history page" do
    test "renders the selected range with its switch active", %{conn: conn} do
      snapshot!(
        taken_at: DateTime.add(now(), -600),
        pv1_power_w: 100,
        pv2_power_w: 50,
        battery_power_w: 20,
        active_power_w: 140,
        grid_power_w: 30
      )

      doc = page(conn, ~p"/solakon/history?range=7d")

      assert texts(doc, "title") == ["Solakon-Verlauf"]
      assert texts(doc, "header.visually-hidden h1") == ["Solakon-Verlauf"]
      assert texts(doc, "#solakon_history a.btn.active") == ["Letzte 7 Tage"]

      assert attrs(doc, "#solakon_history a.btn", "href") ==
               Enum.map(~w(24h 7d 30d), &"/solakon/history?range=#{&1}")

      assert attrs(doc, "#solakon_history[phx-hook=SolakonHistory]", "data-range") == ["7d"]

      assert count(doc, ".solakon-balance-row") == 5

      assert count(
               doc,
               ".solakon-balance-row[data-role='battery'] .progress-bar[style*='background-color: var(--viz-battery)']"
             ) == 2

      assert texts(doc, "[data-role='outlet-average']") == ["Ø Außensteckdose 0 W"]
    end

    test "falls back to 24 h for an unknown or missing range and names the empty state", %{
      conn: conn
    } do
      for path <- [~p"/solakon/history?range=1y", ~p"/solakon/history"] do
        doc = page(conn, path)

        assert texts(doc, "#solakon_history a.btn.active") == ["Letzte 24 h"]
        assert "Keine Solakon-Historie" in texts(doc, ".text-body-secondary")
        assert count(doc, ".solakon-balance-row") == 0
        assert count(doc, "[data-role='outlet-average']") == 0
      end
    end
  end

  describe "connected" do
    test "the nightly aggregation leaves the page running", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/solakon")

      Ziwoas.Plugs.aggregate("Europe/Berlin", [], today: ~D[2026-10-05])

      assert has_element?(view, "#energy_flow")
      assert Process.alive?(view.pid)
    end

    test "plug deltas and readings move the freshness beat, and leave the history be", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/solakon")
      assert_push_event(view, "solakon_history:data", %{range: "24h"})

      send(view.pid, {:live, []})
      assert has_element?(view, "#live_freshness[data-beat='1'] #energy_flow[data-state]")

      send(view.pid, {:reading, reading!([])})
      assert has_element?(view, "#live_freshness[data-beat='2']")
      refute_push_event(view, "solakon_history:data", %{})
    end

    test "the chart's data goes to the hook on mount, and afresh with every stored snapshot", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/solakon")
      assert_push_event(view, "solakon_history:data", %{range: "24h", times: []})
      refute has_element?(view, "#solakon_history .solakon-balance-row")

      snapshot = snapshot!(pv1_power_w: 100)
      send(view.pid, {:snapshot, snapshot})

      assert_push_event(view, "solakon_history:data", %{
        range: "24h",
        times: [_],
        datasets: [
          %{label: "PV", data: [100.0]},
          %{label: "Akku"},
          %{label: "Außensteckdose"},
          %{label: "0 W", data: [0]}
        ]
      })

      assert has_element?(view, "#solakon_history[phx-hook=SolakonHistory] .solakon-balance-row")
      assert has_element?(view, "#solakon_history a.btn.active", "Letzte 24 h")
    end

    test "the history page refreshes on the same event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/solakon/history?range=7d")
      assert_push_event(view, "solakon_history:data", %{range: "7d"})
      refute has_element?(view, "#solakon_history .solakon-balance-row")

      send(view.pid, {:reading, reading!([])})
      snapshot = snapshot!(pv1_power_w: 100)
      send(view.pid, {:snapshot, snapshot})

      assert_push_event(view, "solakon_history:data", %{range: "7d", times: [_]})
      assert has_element?(view, "#solakon_history .solakon-balance-row")
      assert has_element?(view, "#solakon_history a.btn.active", "Letzte 7 Tage")
    end

    test "a range tab swaps the history in place and the refresh keeps that range", %{conn: conn} do
      Repo.insert!(%Snapshot{taken_at: DateTime.add(now(), -3 * 86_400), pv1_power_w: 300.0})
      snapshot = snapshot!(pv1_power_w: 100)
      {:ok, view, _html} = live(conn, ~p"/solakon")

      assert has_element?(view, "#solakon_history a.btn.active", "Letzte 24 h")

      assert_push_event(view, "solakon_history:data", %{
        range: "24h",
        datasets: [%{data: [100.0]} | _]
      })

      view |> element("#solakon_history a", "7 Tage") |> render_click()

      assert_patch(view, ~p"/solakon?range=7d")
      assert has_element?(view, "#solakon_history a.btn.active", "Letzte 7 Tage")
      assert has_element?(view, "#solakon_history[phx-hook=SolakonHistory][data-range='7d']")

      assert_push_event(view, "solakon_history:data", %{
        range: "7d",
        datasets: [%{data: [300.0, 100.0]} | _]
      })

      send(view.pid, {:snapshot, snapshot})

      assert_push_event(view, "solakon_history:data", %{range: "7d"})

      assert has_element?(
               view,
               "#solakon_history[data-range='7d'] a.btn.active",
               "Letzte 7 Tage"
             )
    end

    test "the history page's range tabs swap it in place too", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/solakon/history")

      view |> element("#solakon_history a", "30 Tage") |> render_click()
      assert_patch(view, ~p"/solakon/history?range=30d")
      assert_push_event(view, "solakon_history:data", %{range: "30d"})

      assert has_element?(
               view,
               "#solakon_history[data-range='30d'] a.btn.active",
               "Letzte 30 Tage"
             )
    end
  end
end
