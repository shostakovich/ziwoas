defmodule ZiwoasWeb.ForwardedSSLTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias ZiwoasWeb.ForwardedSSL

  defp call(conn) do
    conn
    |> ForwardedSSL.call(ForwardedSSL.init([]))
    |> put_resp_cookie("look", "felt")
    |> send_resp(200, "ok")
  end

  test "a request the proxy forwarded as HTTPS gets HSTS and Secure cookies" do
    conn =
      conn(:get, "http://ziwoas.example/solakon")
      |> put_req_header("x-forwarded-proto", "https")
      |> call()

    assert conn.status == 200
    assert conn.scheme == :https

    assert get_resp_header(conn, "strict-transport-security") == [
             "max-age=63072000; includeSubDomains"
           ]

    assert [cookie] = get_resp_header(conn, "set-cookie")
    assert cookie =~ "; secure"
  end

  test "a plain HTTP request straight to the port stays HTTP with ordinary cookies" do
    conn = conn(:get, "http://192.168.1.50:3000/solakon") |> call()

    assert conn.scheme == :http
    assert get_resp_header(conn, "strict-transport-security") == []
    assert [cookie] = get_resp_header(conn, "set-cookie")
    refute cookie =~ "secure"
  end

  test "a forwarded http request stays HTTP" do
    conn =
      conn(:get, "http://ziwoas.example/")
      |> put_req_header("x-forwarded-proto", "http")
      |> call()

    assert conn.scheme == :http
  end
end
