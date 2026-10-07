defmodule ZiwoasWeb.AssumeSSLTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias ZiwoasWeb.AssumeSSL

  test "a plain HTTP request counts as HTTPS, with Rails' HSTS header and Secure cookies" do
    conn =
      conn(:get, "http://ziwoas.example/solakon")
      |> AssumeSSL.call(AssumeSSL.init([]))
      |> put_resp_cookie("look", "felt")
      |> send_resp(200, "ok")

    assert conn.status == 200
    assert conn.scheme == :https

    assert get_resp_header(conn, "strict-transport-security") == [
             "max-age=63072000; includeSubDomains"
           ]

    assert [cookie] = get_resp_header(conn, "set-cookie")
    assert cookie =~ "; secure"
  end
end
