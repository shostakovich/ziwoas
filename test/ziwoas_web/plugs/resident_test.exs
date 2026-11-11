defmodule ZiwoasWeb.Plugs.ResidentTest do
  use ZiwoasWeb.ConnCase, async: false

  alias ZiwoasWeb.Plugs.Resident

  defp call(conn) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Resident.call([])
  end

  test "the header from the trusted proxy names the resident", %{conn: conn} do
    conn = conn |> sign_in(" anna ") |> call()

    assert get_session(conn, :resident) == "anna"
  end

  test "the header from any other peer is ignored", %{conn: conn} do
    conn = %{sign_in(conn, "anna") | remote_ip: {192, 168, 1, 50}} |> call()

    assert get_session(conn, :resident) == nil
  end

  test "a request without the header ends the session's resident", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{resident: "anna"})
      |> Resident.call([])

    assert get_session(conn, :resident) == nil
  end

  test "an empty, repeated or overlong header is anonymous", %{conn: conn} do
    assert conn |> sign_in("  ") |> call() |> get_session(:resident) == nil
    assert conn |> sign_in(String.duplicate("a", 65)) |> call() |> get_session(:resident) == nil

    repeated = %{conn | req_headers: [{"x-remote-user", "anna"}, {"x-remote-user", "ben"}]}
    assert repeated |> call() |> get_session(:resident) == nil
  end

  test "an unchanged resident leaves the session cookie alone", %{conn: conn} do
    first = conn |> sign_in("anna") |> get(~p"/sensors")
    assert first.resp_cookies["_ziwoas_key"]

    again = first |> recycle() |> sign_in("anna") |> get(~p"/sensors")
    refute Map.has_key?(again.resp_cookies, "_ziwoas_key")
    assert get_session(again, :resident) == "anna"
  end
end
