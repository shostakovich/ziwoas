defmodule ZiwoasWeb.DashboardLiveTest do
  # Mirrors test/controllers/dashboard_controller_test.rb (the page) and
  # test/dashboard_broadcaster_test.rb (the live regions).
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Repo, TestClock}
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
    test "a live beat re-renders hero, tiles, plug bar and energy flow, and pushes the deltas", %{
      conn: conn
    } do
      {:ok, view, html} = live(conn, ~p"/")
      assert texts(from(html), "#tile_consumption_now .stat-value") == ["—"]

      insert_sample!("fridge", now_ts() - 5, 82.4, 110.0)

      deltas = [
        [{"id", "fridge"}, {"avg_power_w", 82.4}, {"bucket_ts", div(now_ts() - 5, 60) * 60}]
      ]

      send(view.pid, {:dashboard_live, deltas})
      doc = from(render(view))

      assert texts(doc, "#tile_consumption_now .stat-value") == ["82 W"]
      assert texts(doc, "#dashboard_plug_bar strong") == ["82 W"]
      assert attrs(doc, "#live_freshness", "data-beat") == ["1"]
      assert [state] = attrs(doc, "#energy_flow", "data-state")
      assert JSON.decode!(state)["home_w"] == 82.4

      assert_push_event(view, "plug_deltas", %{deltas: [delta]})

      assert delta == %{
               "id" => "fridge",
               "avg_power_w" => 82.4,
               "bucket_ts" => div(now_ts() - 5, 60) * 60
             }
    end

    test "a beat without deltas keeps the plug deltas, an inverter reading beats too", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      send(view.pid, {:dashboard_live, []})
      send(view.pid, {:solakon_reading, 1})
      doc = from(render(view))

      refute_push_event(view, "plug_deltas", _)
      assert attrs(doc, "#live_freshness", "data-beat") == ["2"]
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
