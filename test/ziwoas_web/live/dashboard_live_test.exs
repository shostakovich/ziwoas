defmodule ZiwoasWeb.DashboardLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Plugs, Repo, Sensors, Solakon, TestClock, TestConfigs}
  alias Ziwoas.Plugs.DailyTotal
  alias Ziwoas.Solakon.Reading
  alias Ziwoas.Weather.Record

  @now "2026-10-05T12:00:00+02:00"

  setup do
    TestClock.freeze(@now)
    :ok
  end

  defp now_ts, do: @now |> Clock.parse!() |> DateTime.to_unix()

  defp page(conn), do: conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()
  defp from(html), do: LazyHTML.from_fragment(html)

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp attrs(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()
  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  defp weather!(attrs) do
    defaults = %{kind: :current, lat: 52.52, lon: 13.405, timestamp: Clock.now(), daytime: "day"}
    Repo.insert!(struct!(Record, Map.merge(defaults, Map.new(attrs))))
  end

  test "the page: title, navigation, the energy flow, the tiles and the charts", %{conn: conn} do
    doc = page(conn)

    assert texts(doc, "title") == ["Dashboard"]
    assert texts(doc, "h1") == ["Dashboard"]
    assert texts(doc, "nav[aria-label=Hauptnavigation] a.active") == ["Home"]
    assert count(doc, ".energy-flow > svg[viewBox='0 0 400 320']") == 1
    assert count(doc, ".energy-flow svg g[fill='none'] > circle") == 4
    assert texts(doc, "p.energy-flow-key") == ["Verbraucher-Ring: Herkunft des Stroms"]

    assert texts(doc, "[id^='tile_'] .stat-label") == [
             "Erzeugt heute",
             "Verbraucht heute",
             "Gespart heute",
             "Bilanz heute",
             "Verbrauch jetzt",
             "Bilanz jetzt",
             "Autarkie heute",
             "Eigen­verbrauchs­quote"
           ]

    assert count(doc, "#today_chart[phx-hook=TodayChart] [phx-update=ignore][id] > canvas") == 2

    assert attrs(doc, "#today_chart canvas", "data-chart") == ["energy", "power"]

    assert count(doc, "#history_chart[phx-hook=HistoryChart] [phx-update=ignore][id] > canvas") ==
             1
  end

  test "the energy flow card is the EnergyFlow hook; its SVG keeps its running dots", %{
    conn: conn
  } do
    doc = page(conn)

    assert count(doc, ".energy-flow-card#energy_flow[phx-hook=EnergyFlow][data-state]") == 1
    assert count(doc, "#energy_flow svg#energy_flow_svg[phx-update=ignore]") == 1
  end

  test "the head loads felt-css, then the esbuild bundles: one stylesheet, one script", %{
    conn: conn
  } do
    doc = page(conn)

    assert attrs(doc, "link[rel='stylesheet']", "href") ==
             ["https://felt-css.rocu.de/felt.css", "/assets/css/app.css"]

    assert attrs(doc, "script[src]", "src") == ["/assets/js/app.js"]
    assert count(doc, "script[type='importmap']") == 0
  end

  test "hero, tiles, plug bar and energy flow dim together when the live picture goes stale", %{
    conn: conn
  } do
    doc = page(conn)

    assert attrs(doc, "#live_freshness[phx-hook=LiveFreshness]", "data-threshold-s") == ["120"]
    assert attrs(doc, "#live_freshness", "data-beat") == ["0"]
    assert count(doc, "#live_freshness .live-dim") == 4

    assert count(
             doc,
             "#dashboard_hero.live-dim, #dashboard_plug_bar.live-dim, .energy-flow-card.live-dim"
           ) == 3

    assert count(doc, ".live-dim > #tile_consumption_now") == 1
  end

  test "the battery hero hides itself without a fresh reading and keeps the SVG asset map", %{
    conn: conn
  } do
    doc = page(conn)

    assert count(doc, "#dashboard_hero .col[hidden] img.hero-icon[alt='Batterie']") == 1

    assert count(
             doc,
             "img[data-ef='efBatteryImage'][data-battery-state-charging*='solakon_battery_charging']"
           ) == 1
  end

  test "the current weather icon in the hero and the PV node, the sun without one", %{conn: conn} do
    assert count(page(conn), "img.hero-icon[src*='icon_sonne'][alt='Sonne']") == 1

    weather!(daytime: "night", icon: "cloudy")
    doc = page(conn)
    assert count(doc, "img.hero-icon[src*='weather_cloudy_night'][alt='cloudy']") == 1

    assert count(
             doc,
             ".ef-ring[data-ring='pv'] > img.icon[src*='weather_cloudy_night'][alt='cloudy']"
           ) == 1

    Repo.delete_all(Record)
    weather!(icon: "")
    assert count(page(conn), "img.hero-icon[alt='Sonne']") == 1
  end

  test "live plugs: the consumers' draw, the producer's yield, the day's energy", %{conn: conn} do
    insert_sample!("fridge", now_ts() - 600, 50.0, 100.0)
    insert_sample!("fridge", now_ts() - 5, 82.4, 110.0)
    insert_sample!("bkw", now_ts() - 600, -300.0, 1000.0)
    insert_sample!("bkw", now_ts() - 5, -412.6, 1050.0)

    doc = page(conn)

    assert texts(doc, "#tile_consumption_now .stat-value") == ["82 W"]
    assert texts(doc, "#tile_netbalance_now .stat-value") == ["—"]
    assert texts(doc, "#tile_produced .stat-value") == ["0,05 kWh"]
    assert texts(doc, "#tile_consumed .stat-value") == ["0,01 kWh"]
    assert texts(doc, "#dashboard_hero .col:first-child .display-4") == ["413"]

    assert texts(doc, "#dashboard_plug_bar [data-role='producer']") == [
             "Balkonkraftwerk erzeugt 413 W"
           ]

    assert texts(doc, "#dashboard_plug_bar strong") == ["82 W"]
  end

  describe "connected" do
    test "the charts get their data once connected", %{conn: conn} do
      insert_sample!("fridge", now_ts() - 5, 82.4, 110.0)
      Repo.insert!(%DailyTotal{plug_id: "bkw", date: ~D[2026-10-01], energy_wh: 1500.0})
      Repo.insert!(%DailyTotal{plug_id: "fridge", date: ~D[2026-10-01], energy_wh: 400.0})
      Repo.insert!(%DailyTotal{plug_id: "bkw", date: ~D[2026-09-20], energy_wh: 9.0})

      {:ok, view, _html} = live(conn, ~p"/")

      assert_push_event(view, "today_chart:data", %{series: series})
      fridge = Enum.find(series, &(&1.plug_id == "fridge"))
      assert %{name: "Kühlschrank", role: :consumer} = fridge
      assert fridge.points == [%{ts: div(now_ts() - 5, 60) * 60, avg_power_w: 82.4}]
      assert %{points: []} = Enum.find(series, &(&1.plug_id == "bkw"))

      assert_push_event(view, "history_chart:data", %{
        points: [%{date: "2026-10-01", energy_wh: 1500.0}]
      })
    end

    test "a plug event re-renders hero, tiles, plug bar and energy flow, and pushes the deltas",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")
      assert texts(from(html), "#tile_consumption_now .stat-value") == ["—"]

      insert_sample!("fridge", now_ts() - 5, 82.4, 110.0)
      deltas = [%{id: "fridge", avg_power_w: 82.4, bucket_ts: div(now_ts() - 5, 60) * 60}]

      send(view.pid, {:live, deltas})
      doc = from(render(view))

      assert texts(doc, "#tile_consumption_now .stat-value") == ["82 W"]
      assert texts(doc, "#dashboard_plug_bar strong") == ["82 W"]
      assert attrs(doc, "#live_freshness", "data-beat") == ["1"]
      assert [state] = attrs(doc, "#energy_flow", "data-state")
      assert JSON.decode!(state)["home_w"] == 82.4

      assert_push_event(view, "today_chart:deltas", %{deltas: ^deltas})
    end

    test "an event without deltas pushes none, an inverter reading beats too", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(view.pid, {:live, []})
      send(view.pid, {:reading, %Reading{id: 1}})
      doc = from(render(view))

      refute_push_event(view, "today_chart:deltas", _)
      assert attrs(doc, "#live_freshness", "data-beat") == ["2"]
    end

    test "plug events recompute the day's tiles at most once a minute", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      insert_sample!("bkw", now_ts() - 600, -300.0, 1000.0)
      insert_sample!("bkw", now_ts() - 5, -412.6, 1500.0)

      send(view.pid, {:live, []})
      assert texts(from(render(view)), "#tile_produced .stat-value") == ["0,00 kWh"]

      TestClock.freeze(DateTime.add(Clock.parse!(@now), 60))
      send(view.pid, {:live, []})
      assert texts(from(render(view)), "#tile_produced .stat-value") == ["0,50 kWh"]
    end

    test "midnight starts the day's tiles afresh and redraws the history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert_push_event(view, "history_chart:data", %{points: []})

      insert_sample!("bkw", now_ts() - 600, -300.0, 1000.0)
      insert_sample!("bkw", now_ts() - 5, -412.6, 1500.0)
      Repo.insert!(%DailyTotal{plug_id: "bkw", date: ~D[2026-10-04], energy_wh: 700.0})

      send(view.pid, :midnight)

      assert texts(from(render(view)), "#tile_produced .stat-value") == ["0,50 kWh"]
      assert_push_event(view, "history_chart:data", %{points: [%{energy_wh: 700.0}]})
    end

    test "the nightly aggregation redraws the history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert_push_event(view, "history_chart:data", %{points: []})

      Repo.insert!(%DailyTotal{plug_id: "bkw", date: ~D[2026-10-04], energy_wh: 700.0})
      Plugs.aggregate("Europe/Berlin", [], today: ~D[2026-10-05])

      assert_push_event(view, "history_chart:data", %{points: [%{date: "2026-10-04"}]})
    end

    test "every hour the 24 h window slides on", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert_push_event(view, "today_chart:data", _)

      send(view.pid, :slide_today_chart)
      assert_push_event(view, "today_chart:data", %{series: [_ | _]})
    end

    test "the page listens to Plugs and Solakon", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      insert_sample!("fridge", now_ts() - 5, 12.0, 1.0)

      Solakon.notify_reading(%Reading{id: 7})
      assert texts(from(render(view)), "#tile_consumption_now .stat-value") == ["12 W"]

      Plugs.notify_live([%{id: "fridge"}])
      assert_push_event(view, "today_chart:deltas", %{deltas: [%{id: "fridge"}]})
    end
  end

  describe "the room air tile" do
    test "shows the first room's air verdict and CO₂, and leads to that room", %{conn: conn} do
      Repo.insert!(%Sensors.Reading{device_id: "TEST_INDOOR", taken_at: Clock.now(), co2: 1450})

      doc = page(conn)

      assert texts(doc, "#room_air_tile .stat") == [
               "Wohnzimmer Jetzt lüften CO₂ hoch",
               "CO₂ 1.450 ppm"
             ]

      assert texts(doc, "#room_air_tile .room-air-tile-meta") == ["hoch vor\u00A00\u00A0s"]

      assert attrs(doc, "a#room_air_tile", "href") == ["/sensors#room-wohnzimmer"]
      assert attrs(doc, "a#room_air_tile", "data-phx-link") == ["redirect"]
      assert count(doc, "a#room_air_tile.bg-danger-subtle") == 1
      assert "Raumluft" in texts(doc, "h2.h6")
    end

    test "follows each stored sensor reading, and a silent sensor on the next refresh",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert texts(from(render(view)), "#room_air_tile .stat-value") == [
               "Keine aktuellen Werte",
               "—"
             ]

      {:ok, _reading} = Sensors.create_reading("TEST_INDOOR", Clock.now(), %{co2: 640})
      assert texts(from(render(view)), "#room_air_tile .stat-value") == ["CO₂ gut", "640 ppm"]

      TestClock.freeze(DateTime.add(Clock.parse!(@now), 31 * 60))
      send(view.pid, :refresh_room_air)

      assert texts(from(render(view)), "#room_air_tile .stat-value") == [
               "Keine aktuellen Werte",
               "—"
             ]
    end

    test "shows the SEN66's room, as the TRMNL does, even when another room comes first",
         %{conn: conn} do
      TestConfigs.put(
        TestConfigs.plugs("""
        sensors:
          - { id: KCH, name: Küche, type: meter_pro_co2, room: Küche }
          - { id: SEN, name: Raumluft, type: sen66, room: Wohnzimmer, port: /dev/x }
        """)
      )

      assert texts(page(conn), "#room_air_tile .stat-label") == ["Wohnzimmer", "CO₂"]
    end

    test "stays away without a room that measures CO₂", %{conn: conn} do
      TestConfigs.put(TestConfigs.plugs())

      assert count(page(conn), "#room_air_tile") == 0
    end
  end
end
