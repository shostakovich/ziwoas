defmodule ZiwoasWeb.DashboardLiveTest do
  # Mirrors test/controllers/dashboard_controller_test.rb (the page) and
  # test/dashboard_broadcaster_test.rb (the live regions). The connected
  # LiveView reads this module's database (`Ziwoas.Repo.inherit_dynamic_repo/0`).
  use ZiwoasWeb.ConnCase, async: true, db: true

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Repo}
  alias Ziwoas.Weather.Record

  @now "2026-10-05T12:00:00+02:00"

  setup do
    Clock.freeze(@now)
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
    defaults = %{kind: "current", lat: 52.52, lon: 13.405, timestamp: Clock.now(), daytime: "day"}
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

    assert count(doc, "[data-controller='today-chart'] canvas") == 2
    assert count(doc, "[data-controller='history-chart'] canvas") == 1
    assert attrs(doc, "#plug_deltas", "data-payload") == ["[]"]
  end

  test "the page's scripts load: LiveView from the Hex package, Stimulus controllers from Rails",
       %{
         conn: conn
       } do
    assert get(conn, "/assets/vendor/phoenix_live_view.esm.js").status == 200
    assert get(conn, "/assets/vendor/phoenix.mjs").status == 200

    for path <- ~w[controllers/energy_flow.js controllers/today_chart_controller.js chart.min.js],
        do: assert(get(conn, "/assets/" <> path).status == 200)
  end

  test "hero, tiles, plug bar and energy flow dim together when the live picture goes stale", %{
    conn: conn
  } do
    doc = page(conn)

    assert attrs(
             doc,
             "[data-controller~='live-freshness']",
             "data-live-freshness-threshold-s-value"
           ) == ["120"]

    assert count(doc, "[data-controller~='live-freshness'] .live-dim") == 4

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
             ".ef-ring[data-ring='pv'] > img.ef-icon[src*='weather_cloudy_night'][alt='cloudy']"
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
    test "a live beat re-renders the hero, live tiles, plug bar and a new energy-flow carrier", %{
      conn: conn
    } do
      {:ok, view, html} = live(conn, ~p"/")
      assert texts(from(html), "#tile_consumption_now .stat-value") == ["—"]
      assert count(from(html), "#energy_flow_state") == 1

      insert_sample!("fridge", now_ts() - 5, 82.4, 110.0)

      deltas = [
        [{"id", "fridge"}, {"avg_power_w", 82.4}, {"bucket_ts", div(now_ts() - 5, 60) * 60}]
      ]

      send(view.pid, {:dashboard_live, deltas})
      doc = from(render(view))

      assert texts(doc, "#tile_consumption_now .stat-value") == ["82 W"]
      assert texts(doc, "#dashboard_plug_bar strong") == ["82 W"]
      assert count(doc, "#energy_flow_state") == 0, "a new id: the client replaces the carrier"
      assert [state] = attrs(doc, "[data-energy-flow-target='state']", "data-state")
      assert JSON.decode!(state)["home_w"] == 82.4
      assert [payload] = attrs(doc, "#plug_deltas-1", "data-payload")
      assert [%{"id" => "fridge", "avg_power_w" => 82.4}] = JSON.decode!(payload)
    end

    test "a beat without deltas keeps the plug deltas, an inverter reading beats too", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      send(view.pid, {:dashboard_live, []})
      send(view.pid, {:solakon_reading, 1})
      doc = from(render(view))

      assert attrs(doc, "#plug_deltas", "data-payload") == ["[]"]
      assert count(doc, "#energy_flow_state-2[data-live-freshness-target='beat']") == 1
    end

    test "the summary beat recomputes the day's tiles", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      insert_sample!("bkw", now_ts() - 600, -300.0, 1000.0)
      insert_sample!("bkw", now_ts() - 5, -412.6, 1500.0)
      assert texts(from(render(view)), "#tile_produced .stat-value") == ["0,00 kWh"]

      send(view.pid, {:dashboard_summary})
      assert texts(from(render(view)), "#tile_produced .stat-value") == ["0,50 kWh"]
    end

    test "the page listens on the dashboard and solakon topics", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      insert_sample!("fridge", now_ts() - 5, 12.0, 1.0)

      Phoenix.PubSub.broadcast(Ziwoas.PubSub, "solakon", {:solakon_reading, 7})
      assert texts(from(render(view)), "#tile_consumption_now .stat-value") == ["12 W"]
    end
  end
end
