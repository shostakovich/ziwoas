defmodule ZiwoasWeb.ApiControllerTest do
  # Mirrors test/controllers/api_controller_test.rb; byte parity with Rails is the
  # golden master's job (script/golden_master).
  use ZiwoasWeb.ConnCase

  alias Ziwoas.{Clock, TestClock}

  @now ~U[2026-10-05 10:00:00Z]

  setup %{conn: conn} do
    insert_price!("2020-01-01", "0.2902")
    TestClock.freeze(@now)
    %{conn: put_req_header(conn, "accept", "application/json")}
  end

  defp series(body, plug_id), do: Enum.find(body["series"], &(&1["plug_id"] == plug_id))

  test "GET /api/today returns a series per plug", %{conn: conn} do
    now = Clock.unix_now()
    insert_sample!("bkw", now - 3600, 200.0, 100.0)
    insert_sample!("bkw", now - 3540, 300.0, 110.0)

    body = conn |> get(~p"/api/today") |> json_response(200)

    assert [%{"ts" => _, "avg_power_w" => 200.0} | _] = series(body, "bkw")["points"]
    assert %{"name" => "Balkonkraftwerk", "role" => "producer"} = series(body, "bkw")
    assert series(body, "fridge")["points"] == []
  end

  test "GET /api/today reports producer power as a positive magnitude", %{conn: conn} do
    now = Clock.unix_now()
    insert_sample!("bkw", now - 3600, -200.0, 100.0)
    insert_sample!("fridge", now - 3600, 80.0, 100.0)

    body = conn |> get(~p"/api/today") |> json_response(200)

    assert [%{"avg_power_w" => 200.0}] = series(body, "bkw")["points"]
    assert [%{"avg_power_w" => 80.0}] = series(body, "fridge")["points"]
  end

  test "GET /api/today returns points in ascending ts order", %{conn: conn} do
    now = Clock.unix_now()
    for offset <- [600, 3600, 1800, 7200], do: insert_sample!("bkw", now - offset, 100.0, 100.0)

    timestamps =
      conn
      |> get(~p"/api/today")
      |> json_response(200)
      |> series("bkw")
      |> Map.fetch!("points")
      |> Enum.map(& &1["ts"])

    assert timestamps == Enum.sort(timestamps)
    assert length(timestamps) == 4
  end

  test "GET /api/today/summary saves nothing from energy no consumer took at the time", %{
    conn: conn
  } do
    midnight = berlin_midnight(~D[2026-10-05])
    insert_sample!("bkw", midnight + 60, 0, 0.0)
    insert_sample!("bkw", midnight + 3600, 0, 1000.0)
    insert_sample!("fridge", midnight + 60, 0, 500.0)
    insert_sample!("fridge", midnight + 3600, 0, 600.0)

    body = conn |> get(~p"/api/today/summary") |> json_response(200)

    assert body["produced_wh_today"] == 1000.0
    assert body["consumed_wh_today"] == 100.0
    assert body["savings_eur_today"] == 0.0
    assert body["date"] == "2026-10-05"
  end

  test "GET /api/today/summary keeps Rails' key order", %{conn: conn} do
    raw = conn |> get(~p"/api/today/summary") |> response(200)

    assert raw ==
             ~s({"date":"2026-10-05","produced_wh_today":0.0,"consumed_wh_today":0.0,"self_consumed_wh_today":0.0,) <>
               ~s("autarky_ratio":0.0,"self_consumption_ratio":0.0,"savings_eur_today":0.0})
  end

  test "GET /api/today/summary includes self-consumption", %{conn: conn} do
    midnight = berlin_midnight(~D[2026-10-05])

    for dt <- 0..3600//60 do
      insert_sample!("bkw", midnight + dt, 200.0, 200.0 * dt / 3600.0)
      insert_sample!("fridge", midnight + dt, 100.0, 100.0 * dt / 3600.0)
    end

    body = conn |> get(~p"/api/today/summary") |> json_response(200)

    assert_in_delta body["self_consumed_wh_today"], 100.0, 2.0
    assert_in_delta body["autarky_ratio"], 1.0, 0.05
    assert_in_delta body["self_consumption_ratio"], 0.5, 0.05
    assert_in_delta body["savings_eur_today"], 100.0 * 0.2902 / 1000.0, 0.001
  end

  test "GET /api/today/summary reports no savings while no price is on record", %{conn: conn} do
    Ziwoas.Repo.query!("DELETE FROM electricity_prices")

    assert conn
           |> get(~p"/api/today/summary")
           |> json_response(200)
           |> Map.fetch!("savings_eur_today") == nil
  end

  test "GET /api/history returns the requested number of days, oldest first", %{conn: conn} do
    for i <- 0..6 do
      date = ~D[2026-10-05] |> Date.add(-(i + 1)) |> Date.to_iso8601()

      Ziwoas.Repo.insert!(%Ziwoas.Plugs.DailyTotal{
        plug_id: "bkw",
        date: date,
        energy_wh: 1000.0 + i * 100
      })
    end

    body = conn |> get(~p"/api/history?days=5") |> json_response(200)
    points = series(body, "bkw")["points"]

    assert body["days"] == 5
    assert length(points) == 5
    assert hd(points)["date"] < List.last(points)["date"]
  end

  test "GET /api/history reads days like Ruby's to_i and clamps it to 1..365", %{conn: conn} do
    days = fn query ->
      conn |> get("/api/history" <> query) |> json_response(200) |> Map.fetch!("days")
    end

    assert days.("") == 14
    assert days.("?days=0") == 1
    assert days.("?days=-3") == 1
    assert days.("?days=7abc") == 7
    assert days.("?days=abc") == 1
    assert days.("?days=1000") == 365
  end

  test "an HTML request is not acceptable, as in Rails", %{conn: conn} do
    conn = put_req_header(conn, "accept", "text/html")
    assert_error_sent 406, fn -> get(conn, ~p"/api/today") end
  end
end
