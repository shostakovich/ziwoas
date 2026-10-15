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

  defp energy_flow_state(view) do
    view
    |> element("#energy_flow")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("data-state")
    |> hd()
    |> JSON.decode!()
  end

  defp chart_data(view) do
    view
    |> element("#solakon_history-chart")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("data-chart")
    |> hd()
    |> JSON.decode!()
  end

  @range_link "#solakon_history nav[aria-label=Zeitraum] a[aria-current=page]"

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
    snapshot!(pv1_power_w: 100)
    doc = page(conn)

    assert texts(doc, "title") == ["PV"]
    assert texts(doc, "h1") == ["PV"]
    assert texts(doc, "#app-shell-nav a[aria-current=page]") == ["PV"]
    assert count(doc, "main#main.max-w-5xl") == 1
    assert count(doc, "#live_stale") == 0
    assert count(doc, "#energy_flow[phx-hook=EnergyFlow][data-state]") == 1
    assert count(doc, "#energy_flow svg#energy_flow_svg[phx-update=ignore]") == 1

    sections =
      ~w(Status Steuerung Panels Speicher PV-Verlauf Wirtschaftlichkeit Sonnenkalender Ausbeute)

    assert Enum.filter(texts(doc, "main h2"), &(&1 in sections)) == sections

    assert attrs(doc, "#solakon_history-chart[phx-hook=SolakonHistory]", "data-range") == ["24h"]
    assert texts(doc, "#solakon_history h3.card-title") == ["Leistung"]
    assert texts(doc, "#solakon_history h3.card-title + p") == ["Watt · letzte 24 Stunden"]
    assert count(doc, "#solakon_history-chart[phx-update=ignore] > canvas") == 1
    assert count(doc, "#solakon_history-chart[data-chart]") == 0
    assert count(doc, "#solakon_history script") == 0
    assert texts(doc, @range_link) == ["24 h"]

    assert doc
           |> attrs("#solakon_history nav[aria-label=Zeitraum] a", "data-phx-link-state")
           |> Enum.uniq() == ["replace"]

    assert count(doc, "form#solakon-eps-form[phx-change=toggle_eps] input#solakon-eps-toggle") ==
             1

    assert count(
             doc,
             "form#solakon-control-form[phx-change=toggle_control] input#solakon-control-toggle"
           ) == 1

    assert texts(doc, "#solakon-eps label > span") == ["Notstrom"]
    assert texts(doc, "#solakon-control label > span") == ["Auto-Regelung"]
    assert count(doc, "#solakon-controls label .sr-only") == 0
    assert texts(doc, "#solakon-controls h3") == ["Außensteckdose", "Regelung"]

    assert count(doc, "[data-async=loading]") == 3

    assert texts(doc, "[data-async=loading] a[href='/solakon/wirtschaftlichkeit']") == [
             "Kosten und Preise pflegen"
           ]

    refute LazyHTML.text(doc) =~ ~r/SOH|EPS|46613|39067|Modbus/
    assert count(doc, ".ef-ring[data-ring='pv'] > img.plush[src*='icon_sonne']") == 1
  end

  test "without an inverter configured the auto-regulation is off and cannot be switched", %{
    conn: conn
  } do
    doc = page(conn)

    assert texts(doc, "#solakon-control-meta") == [
             "Aus\u2060\u00A0· in Konfiguration deaktiviert"
           ]

    assert count(doc, "input#solakon-control-toggle[disabled]:not([checked])") == 1
    assert hd(texts(doc, "#solakon-panels")) =~ "Noch keine Panelwerte"
    assert count(doc, "#solakon-panels .stat") == 0
  end

  test "without an inverter configured the outlet cannot be switched", %{conn: conn} do
    assert count(page(conn), "input#solakon-eps-toggle[disabled]:not([checked])") == 1
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

    assert count(doc, "#solakon-controls .card") == 2

    assert texts(doc, "#solakon-panels .stat-title") ==
             ["Panel 1", "Panel 2", "Panel 3", "Panel 4"]

    assert texts(doc, "#solakon-panels .stat-value") == ["211 W", "198 W", "176 W", "0 W"]

    assert hd(texts(doc, "#solakon-panels .stat-desc")) =~ ~r/^41,7 V\S*\s?· 5,12 A$/u

    assert texts(doc, "#solakon-status-details dt") == [
             "Speichertemperatur (Status/Regelung)",
             "Wechselrichtertemperatur",
             "Außensteckdose"
           ]

    assert texts(doc, "#solakon-status-details dd") |> Enum.take(2) == ["24,8 °C", "34,1 °C"]

    assert texts(doc, "#solakon-storage .stat-title") == [
             "Ladestand",
             "Batterie­gesundheit",
             "Aktuelle Batterie­leistung",
             "Batterie­spannung",
             "Batteriestrom",
             "Speicher­temperatur",
             "Volle Kapazität"
           ]

    assert texts(doc, "#solakon-storage .stat-value") ==
             ["— %", "97 %", "— W", "51,3 V", "4,20 A", "24,8 °C", "51,2 Ah"]

    assert count(doc, "#solakon-storage-soc progress") == 0

    assert count(doc, "#solakon_history_balance progress") == 5
    assert texts(doc, "#solakon_history_balance h4") == ["Energie im Zeitraum"]
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

    assert attrs(doc, "#solakon-status img", "data-solakon-battery-state") == ["charging"]
    assert count(doc, "#solakon-status img[src*=solakon_battery_charging]") == 1
    assert texts(doc, "#solakon-status-summary") == ["Akku lädt gerade"]
    assert "84 %" in texts(doc, "#solakon-storage .stat-value")
    assert attrs(doc, "#solakon-storage-soc progress", "value") == ["84"]
    assert attrs(doc, "#solakon-storage-soc progress", "aria-label") == ["Ladestand"]
    assert attrs(doc, "#solakon-storage-soc [data-low]", "data-low") == ["false"]
    assert texts(doc, "#solakon-eps-state") == ["An"]
    assert count(doc, "input#solakon-eps-toggle[checked]") == 1
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

      assert attrs(doc, "#solakon-status img", "data-solakon-battery-state") == [state]
      assert texts(doc, "#solakon-status-summary") == [summary]

      assert attrs(doc, "#solakon-storage-soc [data-low]", "data-low") ==
               [to_string(state == "low")]
    end
  end

  test "the Wirtschaftlichkeit section sits between the history and the sun calendar", %{
    conn: conn
  } do
    assert loaded_page(conn) |> texts("#economics a.btn") == ["Kosten erfassen"]

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

    assert texts(doc, "#economics-cost .stat-value") == ["1.000,00\u00a0€"]
    assert texts(doc, "#economics-saved .stat-value") == ["0,60\u00a0€"]

    assert attrs(doc, "#economics a[href='/solakon/wirtschaftlichkeit']", "href") == [
             "/solakon/wirtschaftlichkeit"
           ]

    {solakon, _} = :binary.match(html, "PV-Verlauf")
    {economics, _} = :binary.match(html, "Wirtschaftlichkeit")
    {calendar, _} = :binary.match(html, "Sonnenkalender")
    assert solakon < economics and economics < calendar
  end

  test "the shading section and the sun calendar, and their empty states", %{conn: conn} do
    empty = loaded_page(conn)
    assert count(empty, "#shading [data-chart]") == 0
    assert hd(texts(empty, "#sun-calendar")) =~ "Noch kein Sonnenkalender"
    assert hd(texts(empty, "#shading")) =~ "Noch keine Ausbeute"

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
    assert count(doc, "#sun-calendar [data-strip]") == 4
    assert count(doc, "#sun-calendar [data-strip='pv'] svg.strip-chart-wide polyline.sun") == 3
    assert "Wechsel der Quelle" in texts(doc, "#sun-calendar li")
    assert count(doc, "#sun-calendar .note") == 1
    assert count(doc, "#shading [data-chart='yield-map'] .fields rect") >= 1
    assert count(doc, "#shading [data-chart='daily-profiles'] .multiple") == 1
    assert count(doc, "#shading [data-chart='panels'] .panel-chart-wide polyline") == 4

    assert texts(doc, "[data-chart='panels'] .card-title + p") == [
             "Stundenmittel in W\u2060\u00a0· seit 01.07.2026 · 3 Tage"
           ]
  end

  test "an outage at mount is marked stale at once, since the newest reading", %{conn: conn} do
    insert_sample!("fridge", DateTime.to_unix(now()) - 900, 82.4, 110.0)
    reading!(taken_at: DateTime.add(now(), -300))

    {:ok, view, _html} = live(conn, ~p"/solakon")
    doc = LazyHTML.from_fragment(render(view))

    assert texts(doc, "header #live_stale") == ["veraltet"]
    assert texts(doc, "header p") == ["Keine neuen Messwerte seit 11:55 Uhr"]
    assert texts(doc, "#solakon-storage-soc .badge") == ["veraltet"]
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

      assert texts(doc, "title") == ["PV-Verlauf"]
      assert texts(doc, "h1") == ["PV-Verlauf"]
      assert texts(doc, "#solakon_history h2.card-title + p") == ["Watt · letzte 7 Tage"]
      assert texts(doc, "main header a[href='/solakon']") == ["PV"]
      assert texts(doc, "#solakon_history nav a[aria-current=page]") == ["7 Tage"]

      assert attrs(doc, "#solakon_history nav a", "href") ==
               Enum.map(~w(24h 7d 30d), &"/solakon/history?range=#{&1}")

      assert attrs(doc, "#solakon_history-chart[phx-hook=SolakonHistory]", "data-range") == ["7d"]

      assert count(doc, "#solakon_history_balance progress") == 5
      assert texts(doc, "#solakon_history_balance h3") == ["Energie im Zeitraum"]
      assert count(doc, "#solakon_history_balance [data-role='battery'] progress") == 2
      assert count(doc, "#solakon_history_balance [data-role='solar'] progress") == 1
      assert texts(doc, "[data-role='outlet-average']") == ["Ø Außensteckdose 0 W"]
    end

    test "falls back to 24 h for an unknown or missing range and names the empty state", %{
      conn: conn
    } do
      for path <- [~p"/solakon/history?range=1y", ~p"/solakon/history"] do
        doc = page(conn, path)

        assert texts(doc, "#solakon_history nav a[aria-current=page]") == ["24 h"]

        assert hd(texts(doc, "#solakon_history [data-role=empty]")) =~
                 "Keine Werte in diesem Zeitraum"

        assert count(doc, "#solakon_history-chart") == 0
        assert count(doc, "#solakon_history_balance") == 0
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

    test "plug deltas and readings redraw the energy flow, and leave the history be", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/solakon")
      refute has_element?(view, "#solakon_history-chart")
      snapshot!(pv1_power_w: 100)

      insert_sample!("fridge", DateTime.to_unix(now()) - 5, 82.4, 110.0)
      send(view.pid, {:live, []})
      assert %{"home_w" => 82.4} = energy_flow_state(view)

      insert_sample!("fridge", DateTime.to_unix(now()) - 1, 90.0, 111.0)
      send(view.pid, {:reading, reading!([])})
      assert %{"home_w" => 90.0} = energy_flow_state(view)
      refute has_element?(view, "#solakon_history-chart")
    end

    test "each reading and snapshot updates status, controls, panels and storage", %{
      conn: conn
    } do
      reading!(battery_soc_pct: 50)
      {:ok, view, _html} = live(conn, ~p"/solakon")
      assert has_element?(view, "#solakon-storage-soc", "50")
      assert has_element?(view, "#solakon-eps-state", "Aus")
      assert has_element?(view, "#solakon-panels", "Noch keine Panelwerte")

      send(
        view.pid,
        {:reading, reading!(battery_soc_pct: 84, battery_power_w: 80, eps_enabled: true)}
      )

      doc = LazyHTML.from_fragment(render(view))
      assert texts(doc, "#solakon-status-summary") == ["Akku lädt gerade"]
      assert texts(doc, "#solakon-status-details dd") |> List.last() == "bereit"
      assert texts(doc, "#solakon-eps-state") == ["An"]
      assert count(doc, "input#solakon-eps-toggle[checked]") == 1
      assert attrs(doc, "#solakon-storage-soc progress", "value") == ["84"]

      send(view.pid, {:snapshot, snapshot!(pv1_power_w: 210)})
      assert has_element?(view, "#solakon-panel-1", "210")
    end

    test "without a reading for two minutes the page is marked stale, not faded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/solakon")

      send(view.pid, :check_freshness)
      doc = LazyHTML.from_fragment(render(view))
      assert count(doc, "#live_stale") == 0

      TestClock.freeze(DateTime.add(now(), 121))
      send(view.pid, :check_freshness)
      doc = LazyHTML.from_fragment(render(view))

      assert texts(doc, "header #live_stale") == ["veraltet"]
      assert texts(doc, "header p") == ["Keine neuen Messwerte seit 12:00 Uhr"]
      assert texts(doc, "#solakon-storage-soc .badge") == ["veraltet"]

      send(view.pid, {:reading, reading!([])})
      refute has_element?(view, "#live_stale")
      refute has_element?(view, "#solakon-storage .badge")
    end

    test "the panels are marked stale with the page", %{conn: conn} do
      snapshot!(pv1_power_w: 100)
      {:ok, view, _html} = live(conn, ~p"/solakon")
      refute has_element?(view, "#solakon-panels .badge")

      TestClock.freeze(DateTime.add(now(), 121))
      send(view.pid, :check_freshness)
      doc = LazyHTML.from_fragment(render(view))

      assert texts(doc, "#solakon-panels .badge") == List.duplicate("veraltet", 4)
    end

    test "the chart's data goes to the hook on mount, and afresh with every stored snapshot", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/solakon")
      assert has_element?(view, "#solakon_history [data-role=empty]")
      refute has_element?(view, "#solakon_history-chart")
      refute has_element?(view, "#solakon_history_balance")

      snapshot = snapshot!(pv1_power_w: 100)
      send(view.pid, {:snapshot, snapshot})

      assert %{
               "times" => [_],
               "datasets" => [
                 %{"key" => "pv", "label" => "PV", "data" => [100.0]},
                 %{"key" => "battery", "label" => "Akku"},
                 %{"key" => "outlet", "label" => "Außensteckdose"}
               ]
             } = chart_data(view)

      assert has_element?(view, "#solakon_history_balance progress")
      assert has_element?(view, @range_link, "24 h")
    end

    test "the history page refreshes on the same event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/solakon/history?range=7d")
      refute has_element?(view, "#solakon_history-chart")
      refute has_element?(view, "#solakon_history_balance")

      send(view.pid, {:reading, reading!([])})
      snapshot = snapshot!(pv1_power_w: 100)
      send(view.pid, {:snapshot, snapshot})

      assert %{"times" => [_]} = chart_data(view)
      assert has_element?(view, "#solakon_history-chart[data-range='7d']")
      assert has_element?(view, "#solakon_history_balance progress")
      assert has_element?(view, @range_link, "7 Tage")
    end

    test "a range tab swaps the history in place and the refresh keeps that range", %{conn: conn} do
      Repo.insert!(%Snapshot{taken_at: DateTime.add(now(), -3 * 86_400), pv1_power_w: 300.0})
      snapshot = snapshot!(pv1_power_w: 100)
      {:ok, view, _html} = live(conn, ~p"/solakon")

      assert has_element?(view, @range_link, "24 h")
      assert %{"datasets" => [%{"data" => [100.0]} | _]} = chart_data(view)

      view |> element("#solakon_history nav a", "7 Tage") |> render_click()

      assert_patch(view, ~p"/solakon?range=7d")
      assert has_element?(view, @range_link, "7 Tage")
      assert has_element?(view, "#solakon_history-chart[data-range='7d']")
      assert %{"datasets" => [%{"data" => [300.0, 100.0]} | _]} = chart_data(view)

      send(view.pid, {:snapshot, snapshot})

      assert has_element?(view, "#solakon_history-chart[data-range='7d']")
      assert has_element?(view, @range_link, "7 Tage")
    end

    test "the history page's range tabs swap it in place too", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/solakon/history")

      view |> element("#solakon_history nav a", "30 Tage") |> render_click()
      assert_patch(view, ~p"/solakon/history?range=30d")

      assert has_element?(view, @range_link, "30 Tage")
      assert has_element?(view, "#solakon_history [data-role=empty]")
    end
  end
end
