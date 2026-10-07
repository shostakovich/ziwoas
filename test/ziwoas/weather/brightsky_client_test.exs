defmodule Ziwoas.Weather.BrightskyClientTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ziwoas.Location
  alias Ziwoas.Weather.BrightskyClient

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

    assert {:ok, weather} = BrightskyClient.current_weather(@location)

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

    assert {:ok, [row]} = BrightskyClient.weather_for_date(@location, ~D[2026-05-04])
    assert row.source_id == 7003
    assert row.timestamp == ~U[2026-05-03 22:00:00.000000Z]
    assert row.icon == "cloudy"
    assert row.daytime == "night"
  end

  test "a 404 for a date is an HTTP status, asked once" do
    expect_get(
      "/weather",
      %{"lat" => "52.52", "lon" => "13.405", "date" => "2026-05-15"},
      404,
      "{}"
    )

    assert BrightskyClient.weather_for_date(@location, ~D[2026-05-15]) ==
             {:error, {:http_status, 404}}

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

    capture_log(fn ->
      assert {:ok, %{icon: "clear-day"}} = BrightskyClient.current_weather(@location)
    end)
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

    capture_log(fn ->
      assert {:ok, %{icon: "rain"}} = BrightskyClient.current_weather(@location)
    end)
  end

  test "gives up after two retries" do
    Req.Test.expect(BrightskyClient, 3, &respond(&1, 502, ""))

    capture_log(fn ->
      assert BrightskyClient.current_weather(@location) == {:error, {:http_status, 502}}
    end)

    Req.Test.verify!(BrightskyClient)
  end

  test "a 4xx is an error without a retry" do
    Req.Test.expect(BrightskyClient, &respond(&1, 400, ""))

    assert BrightskyClient.weather_for_date(@location, ~D[2026-05-04]) ==
             {:error, {:http_status, 400}}

    Req.Test.verify!(BrightskyClient)
  end

  test "a transport error after the retries comes back as the exception" do
    Req.Test.expect(BrightskyClient, 3, &Req.Test.transport_error(&1, :timeout))

    capture_log(fn ->
      assert {:error, %Req.TransportError{reason: :timeout}} =
               BrightskyClient.current_weather(@location)
    end)
  end

  test "garbage is an error" do
    Req.Test.expect(BrightskyClient, &respond(&1, 200, "<html>"))
    assert {:error, {:invalid_json, _}} = BrightskyClient.current_weather(@location)

    Req.Test.expect(BrightskyClient, &respond(&1, 200, "[]"))
    assert BrightskyClient.current_weather(@location) == {:error, :unexpected_body}

    Req.Test.expect(BrightskyClient, &respond(&1, 200, ~s({"weather": [{"icon": "rain"}]})))

    assert BrightskyClient.weather_for_date(@location, ~D[2026-05-04]) ==
             {:error, {:invalid_timestamp, nil}}

    Req.Test.expect(BrightskyClient, &respond(&1, 200, ~s({"weather": {"timestamp": "soon"}})))
    assert BrightskyClient.current_weather(@location) == {:error, {:invalid_timestamp, "soon"}}
  end
end
