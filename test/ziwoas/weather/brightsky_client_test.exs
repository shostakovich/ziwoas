defmodule Ziwoas.Weather.BrightskyClientTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ziwoas.Location
  alias Ziwoas.Weather.BrightskyClient
  alias Ziwoas.Weather.BrightskyClient.Error

  @location %Location{timezone: "Europe/Berlin", lat: 52.52, lon: 13.405}

  defp respond(conn, status, body), do: Plug.Conn.send_resp(conn, status, body)

  defp expect_get(path, query, status, body) do
    Req.Test.expect(BrightskyClient, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == path
      assert URI.decode_query(conn.query_string) == query
      respond(conn, status, body)
    end)
  end

  test "fetches the current weather" do
    expect_get("/current_weather", %{"lat" => "52.52", "lon" => "13.405"}, 200, """
    {"weather": {"timestamp": "2026-05-04T15:00:00+00:00", "source_id": 303711, "temperature": 16.2,
     "condition": "dry", "icon": "cloudy", "cloud_cover": 88, "wind_speed_10": 13.7,
     "precipitation_10": 0.0, "solar_10": 0.072, "relative_humidity": 47, "pressure_msl": 1011.8}}
    """)

    weather = BrightskyClient.current_weather(@location)

    assert weather.timestamp == ~U[2026-05-04 15:00:00.000000Z]
    assert weather.source_id == 303_711
    assert weather.temperature == 16.2
    assert weather.icon == "cloudy"
    assert weather.daytime == "day"
    assert weather.wind_speed == 13.7
    assert weather.precipitation == 0.0
    assert weather.solar == 0.072
    assert weather.sunshine == nil
  end

  test "fetches the hours of a date" do
    expect_get(
      "/weather",
      %{"lat" => "52.52", "lon" => "13.405", "date" => "2026-05-04"},
      200,
      ~s({"weather": [{"timestamp": "2026-05-04T00:00:00+02:00", "source_id": 7003, "icon": "cloudy"}]})
    )

    assert [row] = BrightskyClient.weather_for_date(@location, ~D[2026-05-04])
    assert row.source_id == 7003
    assert row.timestamp == ~U[2026-05-03 22:00:00.000000Z]
    assert row.icon == "cloudy"
    assert row.daytime == "night"
  end

  test "a 404 for a date is the end of the range, asked once" do
    expect_get(
      "/weather",
      %{"lat" => "52.52", "lon" => "13.405", "date" => "2026-05-15"},
      404,
      "{}"
    )

    assert BrightskyClient.weather_for_date(@location, ~D[2026-05-15]) == :range_end
    Req.Test.verify!(BrightskyClient)
  end

  test "retries a transient 5xx, then succeeds" do
    Req.Test.expect(BrightskyClient, &respond(&1, 503, ""))

    Req.Test.expect(BrightskyClient, fn conn ->
      respond(
        conn,
        200,
        ~s({"weather": {"timestamp": "2026-06-12T10:00:00+02:00", "icon": "clear-day"}})
      )
    end)

    capture_log(fn -> assert BrightskyClient.current_weather(@location).icon == "clear-day" end)
  end

  test "retries a transport error, then succeeds" do
    Req.Test.expect(BrightskyClient, &Req.Test.transport_error(&1, :timeout))

    Req.Test.expect(BrightskyClient, fn conn ->
      respond(
        conn,
        200,
        ~s({"weather": {"timestamp": "2026-06-12T10:00:00+02:00", "icon": "rain"}})
      )
    end)

    capture_log(fn -> assert BrightskyClient.current_weather(@location).icon == "rain" end)
  end

  test "gives up after two retries" do
    Req.Test.expect(BrightskyClient, 3, &respond(&1, 502, ""))

    capture_log(fn ->
      assert_raise Error, "Bright Sky HTTP 502", fn ->
        BrightskyClient.current_weather(@location)
      end
    end)

    Req.Test.verify!(BrightskyClient)
  end

  test "a 4xx other than 404 raises without a retry" do
    Req.Test.expect(BrightskyClient, &respond(&1, 400, ""))

    assert_raise Error, "Bright Sky HTTP 400", fn ->
      BrightskyClient.weather_for_date(@location, ~D[2026-05-04])
    end
  end

  test "garbage raises" do
    Req.Test.expect(BrightskyClient, &respond(&1, 200, "<html>"))

    assert_raise Error, ~r/Bright Sky JSON/, fn -> BrightskyClient.current_weather(@location) end
  end
end
