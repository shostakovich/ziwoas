defmodule ZiwoasWeb.DashboardLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Plugs, Repo, Sensors, Solakon, TestClock, TestConfigs}
  alias Ziwoas.Plugs.DailyTotal
  alias Ziwoas.Solakon.{Reading, Snapshot}
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

  defp stat(doc, id),
    do: doc |> LazyHTML.query("##{id}-value > span") |> Enum.map_join(" ", &LazyHTML.text/1)

  defp payload(doc, chart),
    do: doc |> attrs("##{chart}-chart", "data-payload") |> hd() |> JSON.decode!()

  defp weather!(attrs) do
    defaults = %{kind: :current, lat: 52.52, lon: 13.405, timestamp: Clock.now(), daytime: "day"}
    Repo.insert!(struct!(Record, Map.merge(defaults, Map.new(attrs))))
  end

  test "the page: title, navigation, hero, energy flow, tiles, sections and charts", %{conn: conn} do
    doc = page(conn)

    assert texts(doc, "title") == ["Home"]
    assert texts(doc, "h1") == ["Home"]
    assert texts(doc, "#app-shell-nav a[aria-current=page]") == ["Home"]
    assert count(doc, "main#main.max-w-5xl") == 1
    assert count(doc, "#dashboard_hero #hero_pv") == 1
    assert count(doc, ".energy-flow > svg[viewBox='0 0 400 320']") == 1
    assert count(doc, ".energy-flow svg g[fill='none'] > circle") == 4

    assert texts(doc, "[id^='tile_'] .stat-title") == [
             "Verbrauch jetzt",
             "Bilanz jetzt",
             "Erzeugt",
             "Verbraucht",
             "Gespart",
             "Bilanz",
             "Autarkie",
             "Eigen­verbrauchs­quote"
           ]

    assert texts(doc, "main h2") |> Enum.filter(&(&1 in ["Heute", "Verlauf"])) == [
             "Heute",
             "Verlauf"
           ]

    assert attrs(doc, "section.card[aria-busy=true]", "id") ==
             ~w[today_energy today_power history]

    assert count(doc, "[phx-hook=TodayChart], [phx-hook=HistoryChart]") == 0
  end

  test "without a producer Verlauf keeps the 24 h charts and drops the yield history", %{
    conn: conn
  } do
    config = TestConfigs.plugs()
    TestConfigs.put(%{config | plugs: Enum.reject(config.plugs, &(&1.role == :producer))})

    doc = page(conn)

    assert "Verlauf" in texts(doc, "main h2")
    assert attrs(doc, "section.card[aria-busy=true]", "id") == ~w[today_energy today_power]
    assert count(doc, "#history, #history_empty") == 0
    refute "Ertrag je Tag" in texts(doc, ".card-title")
  end

  test "the energy flow card is the EnergyFlow hook; its SVG keeps its running dots", %{
    conn: conn
  } do
    doc = page(conn)

    assert count(doc, "#energy_flow[phx-hook=EnergyFlow][data-state]") == 1
    assert count(doc, "#energy_flow svg#energy_flow_svg[phx-update=ignore]") == 1
  end

  test "the head loads the bundles: one stylesheet, one script", %{conn: conn} do
    doc = page(conn)

    assert attrs(doc, "link[rel='stylesheet']", "href") == ["/assets/css/app.css"]

    assert attrs(doc, "script[src]", "src") == ["/assets/js/app.js"]
    assert count(doc, "script[type='importmap']") == 0
  end

  test "the battery half stays away without a fresh reading", %{conn: conn} do
    doc = page(conn)

    assert count(doc, "#hero_battery") == 0
    assert count(doc, ".ef-ring[data-ring=battery] img[src*='solakon_battery_normal']") == 1
  end

  test "the current weather in German in the hero, the sun without one and in the PV ring", %{
    conn: conn
  } do
    assert count(page(conn), "#dashboard_hero img[src*='icon_sonne'][alt='Sonne']") == 1

    weather!(daytime: "night", icon: "cloudy")
    doc = page(conn)
    assert count(doc, "#dashboard_hero img[src*='weather_cloudy_night'][alt='bewölkt']") == 1
    assert count(doc, ".ef-ring[data-ring='pv'] > img[src*='icon_sonne']") == 1

    Repo.delete_all(Record)
    weather!(icon: "")
    assert count(page(conn), "#dashboard_hero img[src*='icon_sonne'][alt='Sonne']") == 1
  end

  test "the hero's weather turns to night once the sun is down, as on Wetter", %{conn: conn} do
    TestClock.freeze("2026-10-05T23:00:00+02:00")
    weather!(daytime: "day", icon: "cloudy")

    assert count(page(conn), "#dashboard_hero img[src*='weather_cloudy_night']") == 1
  end

  test "live plugs: the consumers' draw, the producer's yield, the day's energy", %{conn: conn} do
    insert_sample!("fridge", now_ts() - 600, 50.0, 100.0)
    insert_sample!("fridge", now_ts() - 5, 82.4, 110.0)
    insert_sample!("bkw", now_ts() - 600, -300.0, 1000.0)
    insert_sample!("bkw", now_ts() - 5, -412.6, 1050.0)

    doc = page(conn)

    assert stat(doc, "tile_consumption_now") == "82 W"
    assert stat(doc, "tile_netbalance_now") == "—"
    assert stat(doc, "tile_produced") == "0,05 kWh"
    assert stat(doc, "tile_consumed") == "0,01 kWh"
    assert texts(doc, "#hero_pv > span:first-child") == ["413"]

    assert texts(doc, "#dashboard_plug_bar [data-role='producer']") == [
             "Balkonkraftwerk erzeugt 413 W"
           ]

    assert texts(doc, "#dashboard_plug_shares li") == ["Kühlschrank 82 W"]
  end

  test "an outage at mount is marked stale at once, since the newest measurement", %{conn: conn} do
    insert_sample!("fridge", now_ts() - 900, 82.4, 110.0)
    insert_sample!("bkw", now_ts() - 600, -300.0, 1000.0)

    doc = page(conn)

    assert texts(doc, "header #live_stale") == ["veraltet"]
    assert texts(doc, "header p") == ["Keine neuen Messwerte seit 11:50 Uhr"]
    assert texts(doc, "#tile_consumption_now .badge") == ["veraltet"]
  end

  describe "connected" do
    test "the charts get their data as hook attributes once connected", %{conn: conn} do
      insert_sample!("fridge", now_ts() - 5, 82.4, 110.0)
      Repo.insert!(%DailyTotal{plug_id: "bkw", date: ~D[2026-10-01], energy_wh: 1500.0})
      Repo.insert!(%DailyTotal{plug_id: "fridge", date: ~D[2026-10-01], energy_wh: 400.0})
      Repo.insert!(%DailyTotal{plug_id: "bkw", date: ~D[2026-09-20], energy_wh: 9.0})

      {:ok, view, _html} = live(conn, ~p"/")
      doc = from(render(view))

      assert attrs(doc, "[phx-hook=TodayChart]", "data-chart") == ~w[energy power]

      %{"series" => series} = payload(doc, "today_power")
      fridge = Enum.find(series, &(&1["plug_id"] == "fridge"))
      assert %{"name" => "Kühlschrank", "role" => "consumer"} = fridge
      assert fridge["points"] == [[div(now_ts() - 5, 60) * 60, 82.4]]
      assert %{"points" => []} = Enum.find(series, &(&1["plug_id"] == "bkw"))

      energy = payload(doc, "today_energy")
      assert length(energy["hours"]) == 25
      assert [%{"plug_id" => "fridge", "name" => "Kühlschrank"}] = energy["consumers"]

      assert payload(doc, "history") == [%{"date" => "2026-10-01", "energy_wh" => 1500.0}]
    end

    test "a plug event re-renders hero, tiles, plug bar and energy flow, and pushes the deltas",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")
      assert stat(from(html), "tile_consumption_now") == "—"

      insert_sample!("fridge", now_ts() - 5, 82.4, 110.0)
      deltas = [%{id: "fridge", avg_power_w: 82.4, bucket_ts: div(now_ts() - 5, 60) * 60}]

      send(view.pid, {:live, deltas})
      doc = from(render(view))

      assert stat(doc, "tile_consumption_now") == "82 W"
      assert texts(doc, "#dashboard_plug_shares li span:last-child") == ["82 W"]
      assert [state] = attrs(doc, "#energy_flow", "data-state")
      assert JSON.decode!(state)["home_w"] == 82.4

      assert_push_event(view, "today_chart:deltas", %{deltas: ^deltas})
    end

    test "an event without deltas pushes none", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(view.pid, {:live, []})
      render(view)

      refute_push_event(view, "today_chart:deltas", _)
    end

    test "without a reading for two minutes the live values are marked stale, not faded",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      send(view.pid, :check_freshness)
      doc = from(render(view))
      assert count(doc, "#live_stale") == 0
      assert texts(doc, ".stat .badge") == []

      TestClock.freeze(DateTime.add(Clock.parse!(@now), 121))
      send(view.pid, :check_freshness)
      doc = from(render(view))

      assert texts(doc, "header #live_stale") == ["veraltet"]
      assert texts(doc, "header p") == ["Keine neuen Messwerte seit 12:00 Uhr"]

      assert texts(doc, "#tile_consumption_now .badge, #tile_netbalance_now .badge") == [
               "veraltet",
               "veraltet"
             ]

      assert texts(doc, "#tile_produced .badge") == []

      send(view.pid, {:reading, %Reading{id: 1}})
      doc = from(render(view))
      assert count(doc, "#live_stale") == 0
      assert texts(doc, ".stat .badge") == []
    end

    test "a plug event clears the stale badge, a room sensor's reading does not", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      TestClock.freeze(DateTime.add(Clock.parse!(@now), 121))
      send(view.pid, :check_freshness)
      assert has_element?(view, "#live_stale")

      send(view.pid, {:reading, %Sensors.Reading{device_id: "TEST_INDOOR"}})
      assert has_element?(view, "#live_stale")

      send(view.pid, {:live, []})
      refute has_element?(view, "#live_stale")
    end

    test "plug events recompute the day's tiles at most once a minute", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      insert_sample!("bkw", now_ts() - 600, -300.0, 1000.0)
      insert_sample!("bkw", now_ts() - 5, -412.6, 1500.0)

      send(view.pid, {:live, []})
      assert stat(from(render(view)), "tile_produced") == "0,00 kWh"

      TestClock.freeze(DateTime.add(Clock.parse!(@now), 60))
      send(view.pid, {:live, []})
      assert stat(from(render(view)), "tile_produced") == "0,50 kWh"
    end

    test "midnight starts the day's tiles afresh and redraws the history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert texts(from(render(view)), "#history_empty p.font-semibold") == [
               "Noch kein Ertrag aufgezeichnet"
             ]

      insert_sample!("bkw", now_ts() - 600, -300.0, 1000.0)
      insert_sample!("bkw", now_ts() - 5, -412.6, 1500.0)
      Repo.insert!(%DailyTotal{plug_id: "bkw", date: ~D[2026-10-04], energy_wh: 700.0})

      send(view.pid, :midnight)
      doc = from(render(view))

      assert stat(doc, "tile_produced") == "0,50 kWh"
      assert [%{"energy_wh" => 700.0}] = payload(doc, "history")
    end

    test "the nightly aggregation redraws the history", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      Repo.insert!(%DailyTotal{plug_id: "bkw", date: ~D[2026-10-04], energy_wh: 700.0})
      Plugs.aggregate("Europe/Berlin", [], today: ~D[2026-10-05])

      assert [%{"date" => "2026-10-04"}] = payload(from(render(view)), "history")
    end

    test "every hour the 24 h window slides on", %{conn: conn} do
      insert_sample!("fridge", now_ts() - 5, 82.4, 110.0)
      {:ok, view, _html} = live(conn, ~p"/")
      assert %{"series" => [%{"points" => []} | _]} = payload(from(render(view)), "today_power")

      insert_sample!("bkw", now_ts() - 5, -412.6, 1500.0)
      send(view.pid, :slide_today_chart)

      assert %{"series" => [%{"points" => [_]} | _]} = payload(from(render(view)), "today_power")
    end

    test "without a reading in 24 hours the charts make way for an empty state until one comes",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      doc = from(render(view))

      assert texts(doc, "#today_empty p.font-semibold") == [
               "Keine Messwerte der letzten 24 Stunden"
             ]

      assert count(doc, "[phx-hook=TodayChart]") == 0

      insert_sample!("fridge", now_ts() - 5, 82.4, 110.0)
      send(view.pid, {:live, [%{id: "fridge", avg_power_w: 82.4, bucket_ts: now_ts() - 5}]})

      assert attrs(from(render(view)), "[phx-hook=TodayChart]", "data-chart") == ~w[energy power]
    end

    test "the page listens to Plugs and Solakon", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      insert_sample!("fridge", now_ts() - 5, 12.0, 1.0)

      Solakon.notify_reading(%Reading{id: 7})
      assert stat(from(render(view)), "tile_consumption_now") == "12 W"

      Plugs.notify_live([%{id: "fridge"}])
      assert_push_event(view, "today_chart:deltas", %{deltas: [%{id: "fridge"}]})
    end

    test "a stored snapshot leaves the page running", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      Solakon.notify_snapshot(%Snapshot{id: 3})

      assert has_element?(view, "#energy_flow")
      assert Process.alive?(view.pid)
    end
  end

  describe "the room air tile" do
    test "shows the room's air verdict and CO₂, and leads to that room", %{conn: conn} do
      Repo.insert!(%Sensors.Reading{device_id: "TEST_INDOOR", taken_at: Clock.now(), co2: 1450})

      doc = page(conn)

      assert texts(doc, "#room_air_tile h2") == ["Raumluft"]
      assert texts(doc, "#room_air_tile h2 + p") == ["Wohnzimmer"]
      assert texts(doc, "#room_air_tile [data-verdict]") == ["Jetzt lüften CO₂ hoch"]
      assert attrs(doc, "#room_air_tile [data-verdict] [data-level]", "data-level") == ["bad"]

      assert texts(doc, "#room_air_tile [data-co2]") == [
               "1.450 ppm CO₂\u2060\u00A0· vor\u00A00\u00A0s"
             ]

      assert attrs(doc, "#room_air_tile a", "href") == ["/sensors#room-wohnzimmer"]
      assert attrs(doc, "#room_air_tile a", "data-phx-link") == ["redirect"]
    end

    test "closes the page, after now, today, the energy flow, the plugs and the charts",
         %{conn: conn} do
      Repo.insert!(%Sensors.Reading{device_id: "TEST_INDOOR", taken_at: Clock.now(), co2: 800})

      landmarks =
        ~w[dashboard_hero today_heading energy_flow dashboard_plug_bar history_heading
           today_energy today_power history room_air_tile]

      ids = attrs(page(conn), Enum.map_join(landmarks, ", ", &"##{&1}"), "id")

      assert ids == landmarks
    end

    test "follows each stored sensor reading, and a silent sensor on the next refresh",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      values = "#room_air_tile :is([data-verdict], [data-co2]) > p:first-child"
      assert texts(from(render(view)), values) == ["Keine aktuellen Werte", "—"]

      {:ok, _reading} = Sensors.create_reading("TEST_INDOOR", Clock.now(), %{co2: 640})
      assert texts(from(render(view)), values) == ["CO₂ gut", "640 ppm"]

      TestClock.freeze(DateTime.add(Clock.parse!(@now), 31 * 60))
      send(view.pid, :refresh_room_air)

      assert texts(from(render(view)), values) == ["Keine aktuellen Werte", "—"]
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

      assert texts(page(conn), "#room_air_tile h2 + p") == ["Wohnzimmer"]
    end

    test "shows the room that needs airing most, the SEN66's room while the air is even",
         %{conn: conn} do
      TestConfigs.put(
        TestConfigs.plugs("""
        sensors:
          - { id: SEN, name: Raumluft, type: sen66, room: Wohnzimmer, port: /dev/x }
          - { id: KCH, name: Küche, type: meter_pro_co2, room: Küche }
          - { id: BAD, name: Bad, type: meter_pro_co2, room: Bad }
        """)
      )

      for {id, co2} <- [{"SEN", 640}, {"KCH", 1100}, {"BAD", 1450}],
          do: Repo.insert!(%Sensors.Reading{device_id: id, taken_at: Clock.now(), co2: co2})

      assert texts(page(conn), "#room_air_tile h2 + p") == ["Bad"]

      Repo.insert!(%Sensors.Reading{
        device_id: "BAD",
        taken_at: DateTime.add(Clock.now(), 1),
        co2: 600
      })

      assert texts(page(conn), "#room_air_tile h2 + p") == ["Küche"]

      Repo.insert!(%Sensors.Reading{
        device_id: "KCH",
        taken_at: DateTime.add(Clock.now(), 1),
        co2: 600
      })

      assert texts(page(conn), "#room_air_tile h2 + p") == ["Wohnzimmer"]
    end

    test "stays away without a room that measures CO₂", %{conn: conn} do
      TestConfigs.put(TestConfigs.plugs())

      assert count(page(conn), "#room_air_tile") == 0
    end
  end
end
