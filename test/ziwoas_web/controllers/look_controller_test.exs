defmodule ZiwoasWeb.LookControllerTest do
  # Mirrors test/controllers/looks_controller_test.rb.
  use ZiwoasWeb.ConnCase, async: true

  test "stores a valid look in a permanent cookie and goes back", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/weather")
      |> patch(~p"/look", %{"look" => "felt"})

    assert redirected_to(conn, 303) == "/weather"
    assert %{value: "felt", max_age: max_age} = conn.resp_cookies["look"]
    assert max_age > 19 * 365 * 24 * 3600
  end

  test "goes to the root without a usable referer", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "https://elsewhere.test/x")
      |> patch(~p"/look", %{"look" => "clean"})

    assert redirected_to(conn, 303) == "/"
  end

  test "rejects an unknown look", %{conn: conn} do
    conn = patch(conn, ~p"/look", %{"look" => "neon"})
    assert conn.status == 400
    refute Map.has_key?(conn.resp_cookies, "look")
  end
end
