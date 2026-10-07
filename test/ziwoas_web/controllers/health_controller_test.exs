defmodule ZiwoasWeb.HealthControllerTest do
  use ZiwoasWeb.ConnCase

  alias Ziwoas.TestClock

  setup do
    TestClock.freeze("2026-10-05T12:00:00+02:00")
    :ok
  end

  test "HTML: a green page", %{conn: conn} do
    for accept <- ["text/html", "*/*", "text/html,application/xhtml+xml,*/*;q=0.8"] do
      conn = conn |> put_req_header("accept", accept) |> get(~p"/up")

      assert response(conn, 200) ==
               ~s(<!DOCTYPE html><html><body style="background-color: green"></body></html>)

      assert response_content_type(conn, :html) =~ "text/html; charset=utf-8"
    end
  end

  test "JSON: status and the local timestamp, by Accept or extension", %{conn: conn} do
    for conn <- [
          conn |> put_req_header("accept", "application/json") |> get(~p"/up"),
          get(conn, "/up.json")
        ] do
      assert json_response(conn, 200) == %{
               "status" => "up",
               "timestamp" => "2026-10-05T12:00:00+02:00"
             }
    end
  end

  @tag :tmp_dir
  test "a device config that does not load is a 503", %{conn: conn, tmp_dir: dir} do
    path = Path.join(dir, "ziwoas.yml")
    File.write!(path, "location: nope\n")
    previous = Application.fetch_env!(:ziwoas, :config_path)
    Application.put_env(:ziwoas, :config_path, path)
    on_exit(fn -> Application.put_env(:ziwoas, :config_path, previous) end)

    assert response(get(conn, ~p"/up"), 503) =~ "red"
    assert %{"status" => "down", "error" => error} = json_response(get(conn, ~p"/up.json"), 503)
    assert error =~ "location"
  end
end
