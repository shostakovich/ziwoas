defmodule ZiwoasWeb.SensorsControllerTest do
  use ZiwoasWeb.ConnCase

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

  test "GET /sensors/series returns JSON with three series", %{conn: conn} do
    reading!("TEST_INDOOR", 30, temperature: 21.0, humidity: 50, co2: 700, battery_pct: 90)
    reading!("TEST_OUTDOOR", 30, temperature: 12.0, humidity: 70, battery_pct: 100)

    conn = get(conn, ~p"/sensors/series")
    body = JSON.decode!(response(conn, 200))

    assert ["application/json; charset=utf-8"] = get_resp_header(conn, "content-type")
    assert Map.keys(body) |> Enum.sort() == ["co2", "humidity", "temperature"]

    indoor = Enum.find(body["temperature"], &(&1["device_id"] == "TEST_INDOOR"))
    assert [[_, 21.0]] = indoor["points"]

    refute "TEST_OUTDOOR" in Enum.map(body["co2"], & &1["device_id"])
  end

  test "points are the last 24 hours in milliseconds, oldest first, without gaps",
       %{conn: conn} do
    reading!("TEST_INDOOR", 24 * 60 + 1, temperature: 19.0, humidity: 40, co2: 500)
    reading!("TEST_INDOOR", 24 * 60, temperature: 20.0, humidity: 41, co2: nil)
    reading!("TEST_INDOOR", 10, temperature: 21.5, humidity: nil, co2: 650)

    body = conn |> get(~p"/sensors/series") |> json_response(200)
    since_ms = (@now |> Clock.parse!() |> DateTime.to_unix(:millisecond)) - 24 * 3600 * 1000
    recent_ms = since_ms + 1430 * 60_000

    assert body == %{
             "temperature" => [
               %{
                 "device_id" => "TEST_INDOOR",
                 "name" => "Test Wohnzimmer",
                 "points" => [[since_ms, 20.0], [recent_ms, 21.5]]
               },
               %{"device_id" => "TEST_OUTDOOR", "name" => "Test Balkon", "points" => []}
             ],
             "humidity" => [
               %{
                 "device_id" => "TEST_INDOOR",
                 "name" => "Test Wohnzimmer",
                 "points" => [[since_ms, 41]]
               },
               %{"device_id" => "TEST_OUTDOOR", "name" => "Test Balkon", "points" => []}
             ],
             "co2" => [
               %{
                 "device_id" => "TEST_INDOOR",
                 "name" => "Test Wohnzimmer",
                 "points" => [[recent_ms, 650]]
               }
             ]
           }
  end

  test "answers JSON whatever the request accepts", %{conn: conn} do
    conn = conn |> put_req_header("accept", "text/html") |> get(~p"/sensors/series")
    assert response(conn, 200) =~ ~s("temperature")
  end
end
