defmodule ZiwoasWeb.WeatherLiveTest do
  # Mirrors test/controllers/weather_controller_test.rb on the disconnected render;
  # markup parity with Rails is the golden master's job.
  use ZiwoasWeb.ConnCase

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
    defaults = %{kind: "forecast", lat: 52.52, lon: 13.405, daytime: "day", icon: "clear-day"}
    Repo.insert!(struct!(Record, Map.merge(defaults, Map.new(attrs))))
  end

  defp page(conn), do: conn |> get(~p"/weather") |> html_response(200) |> LazyHTML.from_document()

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()
  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  test "the empty state without weather data", %{conn: conn} do
    doc = page(conn)
    assert texts(doc, ".card .card-title") == ["Noch keine Wetterdaten"]
    assert hd(texts(doc, ".card p")) =~ "sobald Bright Sky Daten geladen hat"
    assert texts(doc, "nav[aria-label=Hauptnavigation] a.active") == ["Wetter"]
    assert texts(doc, "title") == ["Wetter"]
  end

  test "current weather, today and the next days", %{conn: conn} do
    weather!(
      kind: "current",
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

    assert count(doc, ".card-title") == 0
    assert hd(texts(doc, ".weather-current")) =~ "16,2"
    assert hd(texts(doc, ".weather-current")) =~ "trocken · Wind 10 km/h · DWD"
    assert texts(doc, "h1") == ["Wetter"]
    assert texts(doc, ".weather-hour-row .weather-hour-solar") == ["320", "480"]
    assert count(doc, ".weather-day-card") == 1

    assert doc
           |> LazyHTML.query("ul.weather-hour-key")
           |> Enum.map(&texts(&1, "li.text-nowrap"))
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

    bold? = fn selector ->
      doc
      |> LazyHTML.query(selector)
      |> Enum.map(&("fw-semibold" in String.split(hd(LazyHTML.attribute(&1, "class")))))
    end

    assert bold?.(".weather-hour-row .weather-hour-solar") == [true, false]
    assert bold?.(".weather-hour-row .weather-hour-wind") == [false, true]
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

    assert texts(page(conn), ".weather-hour-row .weather-hour-time") == ["13:00", "22:00"]
  end

  test "the strip hands its bottom padding to a key, rain alone included", %{conn: conn} do
    weather!(
      timestamp: at("2026-05-04T23:00:00"),
      daytime: "night",
      icon: "rain-night",
      temperature: 11.0,
      precipitation: 0.3
    )

    doc = page(conn)
    assert texts(doc, ".weather-hour-row .weather-hour-key > li") == ["Regen in mm"]
    assert count(doc, ".weather-hour-row .weather-hour-scroller.pb-2") == 1
  end

  test "the strip keeps its padding without a key", %{conn: conn} do
    weather!(
      timestamp: at("2026-05-04T23:00:00"),
      daytime: "night",
      icon: "rain-night",
      temperature: 11.0,
      precipitation_probability: 60
    )

    doc = page(conn)
    assert count(doc, ".weather-hour-row .weather-hour-key") == 0
    assert count(doc, ".weather-hour-row .weather-hour-scroller.pb-2") == 0
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
    lists = doc |> LazyHTML.query(".weather-hour-row .weather-hour-extras") |> Enum.to_list()

    assert Enum.map(lists, fn list ->
             list
             |> LazyHTML.query("li")
             |> Enum.map(&(&1 |> LazyHTML.attribute("class") |> hd() |> String.split() |> hd()))
           end) ==
             [
               ~w[weather-hour-wind weather-hour-solar],
               ~w[weather-hour-solar weather-hour-rain],
               ~w[weather-hour-wind weather-hour-rain]
             ]

    assert texts(Enum.at(lists, 1), ".weather-hour-rain") == ["40 %"]
    assert texts(Enum.at(lists, 2), ".weather-hour-rain") == ["1,2"]
    assert texts(Enum.at(lists, 2), ".weather-hour-wind.fw-semibold") == ["25"]

    assert texts(doc, ".weather-hour-row ul.weather-hour-key.flex-wrap > li.text-nowrap") == [
             "Wind in km/h",
             "Sonne in W/m²",
             "Regen in mm"
           ]

    assert "−2°" in texts(doc, ".weather-hour-card strong")
  end

  test "the current card: W/m² by day, a dash without value, Nacht at night", %{conn: conn} do
    weather!(
      kind: "current",
      timestamp: at("2026-05-04T12:00:00"),
      temperature: 20.8,
      solar: 0.072
    )

    assert hd(texts(page(conn), ".weather-current-solar")) =~ "432 W/m²"

    Repo.query!("DELETE FROM weather_records")
    weather!(kind: "current", timestamp: at("2026-05-04T12:00:00"), icon: "cloudy", solar: nil)
    assert texts(page(conn), ".weather-current-solar .tabular-nums") == ["— W/m²"]

    Repo.query!("DELETE FROM weather_records")

    weather!(
      kind: "current",
      timestamp: at("2026-05-04T23:00:00"),
      daytime: "night",
      icon: "clear-night",
      solar: 200.0
    )

    [solar] = texts(page(conn), ".weather-current-solar")
    assert solar =~ "Nacht"
    refute solar =~ "W/m²"
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
    assert texts(doc, ".weather-day-card .weather-day-summary") == ["13 – 17 °C · Regen 1,8 mm"]

    assert texts(doc, ".weather-day-card .card-header > div > h3 + .weather-day-peak") == [
             "Spitze 480 W/m²"
           ]

    assert texts(doc, ".weather-day-card h3") == ["Mittwoch 06.05."]
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
    assert texts(doc, ".weather-day-card .weather-day-summary") == ["14 – 17 °C"]
    assert count(doc, ".weather-day-card .weather-day-peak") == 0
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

    tiles = page(conn) |> LazyHTML.query(".weather-day-card .weather-segment") |> Enum.to_list()

    assert Enum.map(tiles, &texts(&1, "strong.weather-segment-temp.fs-5")) == [
             [],
             ["14 – 14°"],
             ["19 – 19°"],
             []
           ]

    assert Enum.map(tiles, &texts(&1, "span.weather-segment-rain.small.fw-normal")) == [
             [],
             ["0,6 mm"],
             [],
             []
           ]

    assert Enum.map(tiles, &texts(&1, "span.weather-segment-solar.small.text-warning-emphasis")) ==
             [[], ["200 W/m²"], [], []]
  end

  test "four tiles, hidden hour rows, none selected, and the worst icon", %{conn: conn} do
    weather!(timestamp: at("2026-05-05T12:00:00"), temperature: 22.0)
    weather!(timestamp: at("2026-05-05T14:00:00"), icon: "thunderstorm", temperature: 19.0)

    doc = page(conn)

    assert texts(doc, ".weather-day-card .weather-segment-label") ==
             ~w[Nacht Vormittag Nachmittag Abend]

    assert count(doc, ".weather-day-hours .weather-day-hour-row[hidden]") == 4
    assert count(doc, ".weather-segment[phx-click=toggle_segment][aria-expanded=false]") == 4
    assert count(doc, ".weather-segment.active") == 0

    assert doc
           |> LazyHTML.query(".weather-segment")
           |> LazyHTML.attribute("phx-value-index") == ~w[0 1 2 3]

    assert count(doc, ".weather-segment img.weather-segment-icon[src*=weather_thunderstorm_day]") ==
             1
  end

  test "an hour or segment without temperature shows a dash or nothing", %{conn: conn} do
    weather!(timestamp: at("2026-05-04T15:00:00"), icon: "cloudy", temperature: nil)
    weather!(timestamp: at("2026-05-05T09:00:00"), icon: "cloudy", temperature: nil)
    weather!(timestamp: at("2026-05-05T14:00:00"), temperature: 20.0)

    doc = page(conn)
    assert "—°" in texts(doc, ".weather-hour-row .weather-hour-card strong.fs-4")
    assert texts(doc, ".weather-segment-temp") == ["20 – 20°"]
  end

  test "a fresh outdoor sensor reading beats the forecast temperature, a stale one does not", %{
    conn: conn
  } do
    weather!(kind: "current", timestamp: Clock.now(), temperature: 99.9)

    Repo.insert!(%Reading{
      device_id: "TEST_OUTDOOR",
      taken_at: DateTime.add(Clock.now(), -5 * 60),
      temperature: 7.7,
      humidity: 80,
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
      humidity: 80,
      battery_pct: 100
    })

    html = conn |> get(~p"/weather") |> html_response(200)
    assert html =~ "99,9"
    refute html =~ "7,7"
  end

  test "the look cookie sets the felt look", %{conn: conn} do
    doc = conn |> put_req_cookie("look", "felt") |> page()
    assert doc |> LazyHTML.query("html") |> LazyHTML.attribute("data-look") == ["felt"]

    assert doc
           |> LazyHTML.query("button.app-look-toggle.active")
           |> LazyHTML.attribute("aria-pressed") == ["true"]

    assert doc |> LazyHTML.query("input[name=look]") |> LazyHTML.attribute("value") == ["clean"]
  end
end
