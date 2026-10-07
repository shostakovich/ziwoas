defmodule ZiwoasWeb.HealthControllerTest do
  # Rails' rails/health#show; expected bodies from Rails at 2026-10-05 12:00 Berlin.
  use ZiwoasWeb.ConnCase, async: true

  alias Ziwoas.Clock

  setup do
    Clock.freeze("2026-10-05T12:00:00+02:00")
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
      assert response(conn, 200) == ~s({"status":"up","timestamp":"2026-10-05T12:00:00+02:00"})
      assert response_content_type(conn, :json) =~ "application/json; charset=utf-8"
    end
  end
end
