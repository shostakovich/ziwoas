defmodule Ziwoas.Fritz.DectClientTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Fritz.DectClient

  @ain "08761 0500475"
  @sid "abc123def456abcd"

  defp session(sid, challenge \\ "deadbeef"),
    do:
      ~s(<?xml version="1.0" encoding="utf-8"?><SessionInfo><SID>#{sid}</SID>) <>
        ~s(<Challenge>#{challenge}</Challenge><BlockTime>0</BlockTime></SessionInfo>)

  defp client(routes) do
    test = self()

    plug = fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      send(test, {:request, conn.request_path, conn.query_params})
      {status, body} = routes.(conn.request_path, conn.query_params)
      Plug.Conn.send_resp(conn, status, body)
    end

    DectClient.new(host: "fritz.box", user: "u", password: "p", req: [plug: plug])
  end

  defp healthy_box(power \\ "42500\n", energy \\ "1234\n") do
    fn
      "/login_sid.lua", %{"response" => _} -> {200, session(@sid)}
      "/login_sid.lua", _ -> {200, session("0000000000000000")}
      _, %{"switchcmd" => "getswitchpower"} -> {200, power}
      _, %{"switchcmd" => "getswitchenergy"} -> {200, energy}
    end
  end

  describe "fetch/2" do
    test "logs in, then reads power in watts and energy in watt-hours" do
      assert {:ok, %{apower_w: 42.5, aenergy_wh: 1234.0}, %DectClient{sid: @sid}} =
               DectClient.fetch(client(healthy_box()), @ain)

      assert_received {:request, "/login_sid.lua", challenge_request}
      refute Map.has_key?(challenge_request, "response")

      assert_received {:request, "/login_sid.lua",
                       %{"username" => "u", "response" => "deadbeef-" <> _}}

      assert_received {:request, "/webservices/homeautoswitch.lua",
                       %{"switchcmd" => "getswitchpower", "ain" => @ain, "sid" => @sid}}
    end

    test "reuses a session it already holds" do
      client = %{client(healthy_box()) | sid: @sid}

      assert {:ok, _reading, %DectClient{sid: @sid}} = DectClient.fetch(client, @ain)
      refute_received {:request, "/login_sid.lua", _}
    end

    test "a 403 logs in again once and retries the command" do
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      routes = fn
        "/login_sid.lua", %{"response" => _} ->
          {200, session("fresh00000000001")}

        "/login_sid.lua", _ ->
          {200, session("0000000000000000")}

        _, %{"sid" => "expired000000000"} ->
          Agent.update(calls, &(&1 + 1))
          {403, ""}

        _, %{"switchcmd" => "getswitchpower"} ->
          {200, "1000"}

        _, %{"switchcmd" => "getswitchenergy"} ->
          {200, "7"}
      end

      client = %{client(routes) | sid: "expired000000000"}

      assert {:ok, %{apower_w: 1.0, aenergy_wh: 7.0}, %DectClient{sid: "fresh00000000001"}} =
               DectClient.fetch(client, @ain)

      assert Agent.get(calls, & &1) == 1
    end

    test "a 403 after the new login is an error" do
      routes = fn
        "/login_sid.lua", %{"response" => _} -> {200, session(@sid)}
        "/login_sid.lua", _ -> {200, session("0000000000000000")}
        _, _ -> {403, ""}
      end

      assert {:error, :forbidden_after_reauth, %DectClient{sid: @sid}} =
               DectClient.fetch(%{client(routes) | sid: "expired000000000"}, @ain)
    end

    test "a rejected password is an authentication error and keeps no session" do
      routes = fn "/login_sid.lua", _ -> {200, session("0000000000000000")} end

      assert {:error, :auth_failed, %DectClient{sid: nil}} =
               DectClient.fetch(client(routes), @ain)
    end

    test "an empty session id is an authentication error" do
      routes = fn "/login_sid.lua", _ -> {200, session("")} end

      assert {:error, :auth_failed, %DectClient{sid: nil}} =
               DectClient.fetch(client(routes), @ain)
    end

    test "an HTTP error during login names the status" do
      routes = fn "/login_sid.lua", _ -> {500, ""} end

      assert {:error, {:auth_status, 500}, %DectClient{sid: nil}} =
               DectClient.fetch(client(routes), @ain)
    end

    test "an invalid login page reads as a missing challenge" do
      routes = fn "/login_sid.lua", _ -> {200, "<html>no xml"} end

      assert {:error, :no_challenge, _} = DectClient.fetch(client(routes), @ain)
    end

    test "an HTTP error from a command names the status" do
      routes = fn
        "/login_sid.lua", %{"response" => _} -> {200, session(@sid)}
        "/login_sid.lua", _ -> {200, session("0000000000000000")}
        _, _ -> {500, "oops"}
      end

      assert {:error, {:http_status, 500}, %DectClient{sid: @sid}} =
               DectClient.fetch(client(routes), @ain)
    end

    test "a blank answer is an error" do
      assert {:error, :blank_response, _} =
               DectClient.fetch(client(healthy_box(" \n")), @ain)
    end

    test "an unknown plug answers inval, which is an unexpected response" do
      assert {:error, {:unexpected_response, "inval"}, _} =
               DectClient.fetch(client(healthy_box("inval\n")), @ain)

      assert {:error, {:unexpected_response, "1.5"}, _} =
               DectClient.fetch(client(healthy_box("1000", "1.5")), @ain)
    end

    test "a timeout is a network error" do
      plug = fn conn -> Req.Test.transport_error(conn, :timeout) end
      client = DectClient.new(host: "fritz.box", user: "u", password: "p", req: [plug: plug])

      assert {:error, %Req.TransportError{reason: :timeout}, %DectClient{sid: nil}} =
               DectClient.fetch(client, "1")
    end

    test "a timeout during a command keeps the session" do
      plug = fn conn -> Req.Test.transport_error(conn, :timeout) end

      client = %{
        DectClient.new(host: "fritz.box", user: "u", password: "p", req: [plug: plug])
        | sid: @sid
      }

      assert {:error, %Req.TransportError{reason: :timeout}, %DectClient{sid: @sid}} =
               DectClient.fetch(client, @ain)
    end
  end

  describe "response/2" do
    test "an MD5 challenge is answered over UTF-16LE" do
      md5 =
        :crypto.hash(
          :md5,
          :unicode.characters_to_binary("deadbeef-testpass", :utf8, {:utf16, :little})
        )

      assert DectClient.response("deadbeef", "testpass") ==
               "deadbeef-" <> Base.encode16(md5, case: :lower)
    end

    test "a PBKDF2 challenge is answered with salt2 and the twice-derived hash" do
      assert DectClient.response("2$10000$5A1711$2000$5A1722", "1example!") ==
               "5A1722$1798a1672bca7c6463d6b245f82b53703b0f50813401b03e4045a5861e689adb"
    end
  end
end
