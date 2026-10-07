defmodule ZiwoasWeb.SensorsLiveTest do
  # Mirrors test/controllers/sensors_controller_test.rb (the page) and the
  # partial-level checks of test/sensors_broadcaster_test.rb (the live update).
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Repo, TestClock}
  alias Ziwoas.Sensors.Reading

  @now "2026-05-04T12:00:00+02:00"

  setup do
    TestClock.freeze(@now)
    :ok
  end

  defp reading!(device_id, minutes_ago, attrs) do
    taken_at = @now |> Clock.parse!() |> DateTime.add(-minutes_ago * 60, :second)
    Repo.insert!(struct!(%Reading{device_id: device_id, taken_at: taken_at}, attrs))
  end

  defp page(conn),
    do: conn |> get(~p"/sensors") |> html_response(200) |> LazyHTML.from_document()

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp attrs(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()
  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  defp card(doc, name),
    do: doc |> LazyHTML.query("article.card") |> Enum.find(&(LazyHTML.text(&1) =~ name))

  test "GET /sensors returns 200", %{conn: conn} do
    assert conn |> get(~p"/sensors") |> html_response(200) =~ "Sensoren"
  end

  test "GET /sensors shows a card per sensor with the CO₂ gauge", %{conn: conn} do
    reading!("TEST_INDOOR", 5, temperature: 21.0, humidity: 50, co2: 1200, battery_pct: 90)
    reading!("TEST_OUTDOOR", 5, temperature: 12.0, humidity: 70, battery_pct: 100)

    doc = page(conn)
    indoor = card(doc, "Test Wohnzimmer")
    outdoor = card(doc, "Test Balkon")

    assert LazyHTML.attribute(LazyHTML.query(indoor, "svg.co2-gauge"), "aria-label") == [
             "CO₂ 1.200 ppm, erhöht"
           ]

    assert texts(indoor, "li") == ["21,0 °C", "50 % rH", "1.200 ppm"]
    assert texts(indoor, ".small.text-body-secondary") == ["vor 5 Min"]
    assert count(outdoor, "svg.co2-gauge") == 0
    assert count(doc, ".alert") == 0

    assert count(doc, "section[aria-label=Sensoren].row-cols-sm-2.row-cols-lg-2") == 1,
           "two sensors fill a row of two on desktops instead of leaving a third slot empty"

    assert attrs(doc, "#sensors_chart[phx-hook=SensorsChart]", "data-url") == ["/sensors/series"]

    assert attrs(doc, "#sensors_chart [phx-update=ignore][id] > canvas", "data-series") ==
             ~w[co2 temperature humidity]

    assert texts(doc, "#sensors_chart .card-subtitle") == [
             "ppm · Test Wohnzimmer · letzte 24 h",
             "°C · letzte 24 h",
             "Prozent · letzte 24 h"
           ]

    assert texts(doc, "title") == ["Sensoren"]
    assert texts(doc, "nav[aria-label=Hauptnavigation] a.active") == ["Sensoren"]
  end

  test "GET /sensors warns about sensors with a low battery", %{conn: conn} do
    reading!("TEST_INDOOR", 5, temperature: 21.0, co2: 600, battery_pct: 90)
    reading!("TEST_OUTDOOR", 5, temperature: 12.0, battery_pct: 15)

    assert texts(page(conn), ".alert.alert-warning[role=alert]") == [
             "Batterie schwach: Test Balkon"
           ]
  end

  test "a sensor without readings says so", %{conn: conn} do
    reading!("TEST_INDOOR", 5, temperature: 21.0, co2: 600, battery_pct: 90)

    assert texts(card(page(conn), "Test Balkon"), "p") == ["Keine Daten"]
  end

  test "GET /sensors shows the empty state without readings", %{conn: conn} do
    doc = page(conn)

    assert texts(doc, ".card .card-title") == ["Noch keine Sensordaten"]
    assert hd(texts(doc, ".card p")) =~ "sobald die SwitchBot-API Daten geliefert hat"
    assert count(doc, "#sensors_chart") == 0
  end

  test "a sensor update re-renders the dashboard with the newest readings", %{conn: conn} do
    reading!("TEST_INDOOR", 20, temperature: 21.0, humidity: 50, co2: 800, battery_pct: 90)
    {:ok, view, _html} = live(conn, ~p"/sensors")

    assert render(view) =~ "21,0"
    refute has_element?(view, ".alert")

    reading!("TEST_INDOOR", 0, temperature: 23.4, humidity: 48, co2: 1500, battery_pct: 10)
    Phoenix.PubSub.broadcast(Ziwoas.PubSub, "sensors", {:sensors_updated})

    doc = view |> render() |> LazyHTML.from_fragment()
    indoor = card(doc, "Test Wohnzimmer")

    assert texts(indoor, "li") == ["23,4 °C", "48 % rH", "1.500 ppm"]
    assert texts(indoor, ".small.text-body-secondary") == ["vor 0 s"]

    assert LazyHTML.attribute(LazyHTML.query(indoor, "svg.co2-gauge"), "aria-label") == [
             "CO₂ 1.500 ppm, schlecht"
           ]

    assert texts(doc, ".alert") == ["Batterie schwach: Test Wohnzimmer"]
    assert_push_event(view, "sensors_updated", %{})
  end

  test "the first reading replaces the empty state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sensors")
    assert has_element?(view, ".card-title", "Noch keine Sensordaten")

    reading!("TEST_OUTDOOR", 1, temperature: 12.0, humidity: 70, battery_pct: 100)
    send(view.pid, {:sensors_updated})

    refute has_element?(view, ".card-title", "Noch keine Sensordaten")
    assert has_element?(view, "#sensors_chart[phx-hook=SensorsChart]")
  end
end
