defmodule ZiwoasWeb.HealthControllerTest do
  use ZiwoasWeb.ConnCase, async: false

  alias Ziwoas.{Config, TestConfigs}

  test "up while the device config is loaded, whatever the request accepts", %{conn: conn} do
    for accept <- ["text/html", "*/*", "application/json"] do
      conn = conn |> put_req_header("accept", accept) |> get(~p"/up")
      assert json_response(conn, 200) == %{"status" => "up"}
    end
  end

  test "a device config that did not load is a 503 naming the error", %{conn: conn} do
    TestConfigs.put(Config.from_yaml("location: nope\n"))

    assert %{"status" => "down", "error" => error} = json_response(get(conn, ~p"/up"), 503)
    assert error =~ "location"
  end

  test "/up.json is gone", %{conn: conn} do
    assert response(get(conn, "/up.json"), 404)
  end
end
