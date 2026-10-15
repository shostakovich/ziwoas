defmodule ZiwoasWeb.WeatherLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Repo, TestClock}
  alias Ziwoas.Sensors.Reading
  alias Ziwoas.Weather.Record

  setup do
    TestClock.freeze("2026-05-04T12:00:00+02:00")
    :ok
  end

  defp at(text),
    do:
      text
      |> NaiveDateTime.from_iso8601!()
      |> DateTime.from_naive!("Europe/Berlin")
      |> usec()

  defp weather!(attrs) do
    defaults = %{kind: :forecast, lat: 52.52, lon: 13.405, daytime: "day", icon: "clear-day"}
    Repo.insert!(struct!(Record, Map.merge(defaults, Map.new(attrs))))
  end

  defp page(conn), do: conn |> get(~p"/weather") |> html_response(200) |> LazyHTML.from_document()

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp attrs(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp squish(text),
    do: text |> String.replace(["\u00A0", "\u2060"], " ") |> String.split() |> Enum.join(" ")

  defp emphasised(doc, selector),
    do:
      doc
      |> LazyHTML.query(selector)
      |> Enum.map(&(LazyHTML.attribute(&1, "data-emphasis") == ["true"]))

  test "the empty state without weather data", %{conn: conn} do
    doc = page(conn)
    assert texts(doc, "main h2") == ["Noch keine Wetterdaten"]
    assert hd(texts(doc, "main h2 + p")) =~ "sobald Bright Sky Daten geladen hat"
    assert texts(doc, "#app-shell-nav a[aria-current=page]") == ["Wetter"]
    assert texts(doc, "title") == ["Wetter"]
  end

  test "current weather, today and the next days", %{conn: conn} do
    weather!(
      kind: :current,
      timestamp: at("2026-05-04T12:00:00"),
      icon: "cloudy",
      temperature: 16.2,
      condition: "dry",
      wind_speed: 9.7,
      relative_humidity: 80,
      cloud_cover: 100,
      precipitation: 0.0,
      pressure_msl: 1011.6
    )

    weather!(
      timestamp: at("2026-05-04T13:00:00"),
      icon: "partly-cloudy-day",
      temperature: 18.0,
      precipitation: 0.0,
      solar: 0.32,
      wind_speed: 11.0
    )

    weather!(
      timestamp: at("2026-05-05T12:00:00"),
      temperature: 20.0,
      precipitation_probability: 4,
      solar: 0.48,
      wind_speed: 12.0
    )

    doc = page(conn)

    refute LazyHTML.text(doc) =~ "Noch keine Wetterdaten"
    assert texts(doc, "#weather-now") == ["Jetzt 16,2 °C trocken · Wind 10 km/h · DWD"]
    assert attrs(doc, "#weather-now [role=img]", "aria-label") == ["bewölkt"]
    assert attrs(doc, "#weather-solar img", "alt") == [""]

    assert texts(doc, "#weather-current [data-measure]") == [
             "Luftfeuchte 80 %",
             "Wolken 100 %",
             "Regen 0,0 mm",
             "Luftdruck 1.012 hPa"
           ]

    assert texts(doc, "h1") == ["Wetter"]
    assert texts(doc, "#weather-today [data-row=solar]") == ["320", "480"]
    assert attrs(doc, "#weather-forecast article", "id") == ["day-2026-05-05"]

    assert doc
           |> LazyHTML.query("[data-hour-key]")
           |> Enum.map(&texts(&1, "li"))
           |> Enum.uniq() ==
             [["Wind in km/h", "Sonne in W/m²"]]
  end

  test "the sun is bold from 400 W/m², the wind from 20 km/h", %{conn: conn} do
    weather!(
      timestamp: at("2026-05-04T13:00:00"),
      temperature: 22.0,
      solar: 0.4,
      wind_speed: 19.0
    )

    weather!(
      timestamp: at("2026-05-04T14:00:00"),
      temperature: 22.0,
      solar: 0.399,
      wind_speed: 20.0
    )

    doc = page(conn)

    assert emphasised(doc, "#weather-today [data-row=solar]") == [true, false]
    assert emphasised(doc, "#weather-today [data-row=wind]") == [false, true]
  end

  test "today runs from this hour to the end of tomorrow", %{conn: conn} do
    weather!(timestamp: at("2026-05-04T09:00:00"), temperature: 12.0)
    weather!(timestamp: at("2026-05-04T13:00:00"), temperature: 18.0, solar: 0.32)

    weather!(
      timestamp: at("2026-05-05T22:00:00"),
      daytime: "night",
      icon: "clear-night",
      temperature: 10.0
    )

    assert texts(page(conn), "#weather-today time") == ["13:00", "22:00"]
  end

  test "the strip's key names the rows' units, rain alone included", %{conn: conn} do
    weather!(
      timestamp: at("2026-05-04T23:00:00"),
      daytime: "night",
      icon: "rain-night",
      temperature: 11.0,
      precipitation: 0.3
    )

    assert texts(page(conn), "#weather-today [data-hour-key] li") == ["Regen in mm"]
  end

  test "a chance of rain alone needs no key", %{conn: conn} do
    weather!(
      timestamp: at("2026-05-04T23:00:00"),
      daytime: "night",
      icon: "rain-night",
      temperature: 11.0,
      precipitation_probability: 60
    )

    doc = page(conn)
    assert texts(doc, "#weather-today [data-row=rain]") == ["60 %"]
    assert count(doc, "#weather-today [data-hour-key]") == 0
  end

  test "every hour card renders the strip's rows it has something for, rain last", %{conn: conn} do
    weather!(
      timestamp: at("2026-05-04T13:00:00"),
      icon: "partly-cloudy-day",
      temperature: 18.0,
      precipitation: 0.0,
      solar: 0.32,
      wind_speed: 11.0
    )

    weather!(
      timestamp: at("2026-05-04T14:00:00"),
      icon: "rain-day",
      temperature: 17.0,
      precipitation: 0.0,
      precipitation_probability: 40,
      solar: 0.1
    )

    weather!(
      timestamp: at("2026-05-04T23:00:00"),
      daytime: "night",
      icon: "rain-night",
      temperature: -2.0,
      precipitation: 1.2,
      wind_speed: 25.0
    )

    doc = page(conn)
    lists = doc |> LazyHTML.query("#weather-today article ul") |> Enum.to_list()

    assert Enum.map(lists, &(&1 |> LazyHTML.query("li") |> LazyHTML.attribute("data-row"))) ==
             [~w[wind solar], ~w[solar rain], ~w[wind rain]]

    assert texts(Enum.at(lists, 1), "[data-row=rain]") == ["40 %"]
    assert texts(Enum.at(lists, 2), "[data-row=rain]") == ["1,2"]
    assert texts(Enum.at(lists, 2), "[data-row=wind][data-emphasis=true]") == ["Wind in km/h 25"]

    assert attrs(Enum.at(lists, 2), "[data-row=rain] img", "alt") == ["Regen in mm"]

    assert texts(doc, "#weather-today [data-hour-key] li") == [
             "Wind in km/h",
             "Sonne in W/m²",
             "Regen in mm"
           ]

    assert Enum.at(texts(doc, "#weather-today article"), 2) =~ "−2°"
  end

  test "the current card: W/m² by day, a dash without value, Nacht at night", %{conn: conn} do
    weather!(
      kind: :current,
      timestamp: at("2026-05-04T12:00:00"),
      temperature: 20.8,
      solar: 0.072
    )

    assert texts(page(conn), "#weather-solar") == ["Sonne 432 W/m²"]

    Repo.query!("DELETE FROM weather_records")
    weather!(kind: :current, timestamp: at("2026-05-04T12:00:00"), icon: "cloudy", solar: nil)
    assert texts(page(conn), "#weather-solar") == ["Sonne — W/m²"]

    Repo.query!("DELETE FROM weather_records")

    weather!(
      kind: :current,
      timestamp: at("2026-05-04T23:00:00"),
      daytime: "night",
      icon: "clear-night",
      solar: 200.0
    )

    assert texts(page(conn), "#weather-solar") == ["Sonne Nacht"]
  end

  test "after sunset the current card shows no sun, though the record is from daylight", %{
    conn: conn
  } do
    TestClock.freeze("2026-05-04T22:30:00+02:00")

    weather!(
      kind: :current,
      timestamp: at("2026-05-04T20:00:00"),
      icon: "partly-cloudy-day",
      solar: 0.003
    )

    doc = page(conn)
    assert texts(doc, "#weather-solar") == ["Sonne Nacht"]
    assert [_ | _] = sources = attrs(doc, "#weather-now img", "src")
    assert Enum.all?(sources, &(&1 =~ "partly_cloudy_night"))
  end

  test "the day card's summary and peak", %{conn: conn} do
    for {hour, temp, precip, solar} <- [
          {"06", 13.0, 0.4, 0.22},
          {"12", 17.0, 0.0, 0.48},
          {"18", 14.0, 1.4, 0.09}
        ] do
      weather!(
        timestamp: at("2026-05-06T#{hour}:00:00"),
        icon: "partly-cloudy-day",
        temperature: temp,
        precipitation: precip,
        solar: solar
      )
    end

    doc = page(conn)
    assert texts(doc, "#day-2026-05-06 h3 + p") == ["13–17 °C · Regen 1,8 mm"]
    assert texts(doc, "#day-2026-05-06 [data-peak]") == ["Spitze 480 W/m²"]
    assert texts(doc, "#day-2026-05-06 h3") == ["Mittwoch, 06.05."]
  end

  test "no rain summary and no peak without them", %{conn: conn} do
    weather!(
      timestamp: at("2026-05-06T12:00:00"),
      icon: "cloudy",
      temperature: 17.0,
      precipitation: 0.0
    )

    weather!(
      timestamp: at("2026-05-06T18:00:00"),
      icon: "cloudy",
      temperature: 14.0,
      precipitation: nil
    )

    doc = page(conn)
    assert texts(doc, "#day-2026-05-06 h3 + p") == ["14–17 °C"]
    assert count(doc, "#day-2026-05-06 [data-peak]") == 0
  end

  test "the segment tiles share the day's rows, each renders those it has", %{conn: conn} do
    weather!(
      timestamp: at("2026-05-06T09:00:00"),
      icon: "rain-day",
      temperature: 14.0,
      precipitation: 0.6,
      solar: 0.2
    )

    weather!(timestamp: at("2026-05-06T15:00:00"), temperature: 19.0, precipitation: 0.0)

    tiles =
      page(conn) |> LazyHTML.query("#day-2026-05-06 button[aria-controls]") |> Enum.to_list()

    assert Enum.map(tiles, &texts(&1, "[data-row=temp][data-emphasis=true]")) == [
             [],
             ["14°"],
             ["19°"],
             []
           ]

    assert Enum.map(tiles, &texts(&1, "[data-row=rain]")) == [[], ["0,6 mm"], [], []]
    assert Enum.map(tiles, &texts(&1, "[data-row=solar]")) == [[], ["200 W/m²"], [], []]
  end

  test "four tiles, hidden hour rows, none selected, and the worst icon", %{conn: conn} do
    weather!(timestamp: at("2026-05-05T12:00:00"), temperature: 22.0)
    weather!(timestamp: at("2026-05-05T14:00:00"), icon: "thunderstorm", temperature: 19.0)

    doc = page(conn)

    assert texts(doc, "#day-2026-05-05 button[aria-controls] > span:first-child") ==
             ~w[Nacht Vormittag Nachmittag Abend]

    assert count(doc, "#day-2026-05-05 [role=region][id^=seg-][hidden]") == 4
    assert count(doc, "button[phx-click=toggle_segment][aria-expanded=false]") == 4
    assert count(doc, "[aria-expanded=true]") == 0

    assert attrs(doc, "button[phx-click=toggle_segment]", "phx-value-index") == ~w[0 1 2 3]

    assert attrs(doc, "button[phx-value-index='2'] img[src*=weather_thunderstorm_day]", "alt") ==
             ["Gewitter"]
  end

  test "an hour or segment without temperature shows a dash or nothing", %{conn: conn} do
    weather!(timestamp: at("2026-05-04T15:00:00"), icon: "cloudy", temperature: nil)
    weather!(timestamp: at("2026-05-05T09:00:00"), icon: "cloudy", temperature: nil)
    weather!(timestamp: at("2026-05-05T14:00:00"), temperature: 20.0)

    doc = page(conn)
    assert hd(texts(doc, "#weather-today article")) =~ "—°"
    assert texts(doc, "[data-row=temp]") == ["20°"]
  end

  test "a fresh outdoor sensor reading beats the forecast temperature, a stale one does not", %{
    conn: conn
  } do
    weather!(kind: :current, timestamp: Clock.now(), temperature: 99.9)

    Repo.insert!(%Reading{
      device_id: "TEST_OUTDOOR",
      taken_at: DateTime.add(Clock.now(), -5 * 60),
      temperature: 7.7,
      humidity: 80.0,
      battery_pct: 100
    })

    html = conn |> get(~p"/weather") |> html_response(200)
    assert html =~ "7,7" and html =~ "eigener Sensor"
    refute html =~ "99,9"

    Repo.query!("DELETE FROM sensor_readings")

    Repo.insert!(%Reading{
      device_id: "TEST_OUTDOOR",
      taken_at: DateTime.add(Clock.now(), -2 * 3600),
      temperature: 7.7,
      humidity: 80.0,
      battery_pct: 100
    })

    html = conn |> get(~p"/weather") |> html_response(200)
    assert html =~ "99,9"
    refute html =~ "7,7"
  end

  test "a stored sensor reading leaves the page as it is", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/weather")

    send(view.pid, {:reading, %Reading{device_id: "TEST_OUTDOOR"}})

    assert render(view) =~ "Wetter"
  end
end
