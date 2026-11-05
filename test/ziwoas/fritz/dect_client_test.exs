defmodule Ziwoas.Fritz.DectClientTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Fritz.{DectClient, Thermostat}

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

  describe "thermostats/1" do
    @device_list File.read!(Path.expand("../../fixtures/fritz_devicelist.xml", __DIR__))

    defp device_box(body) do
      fn
        "/login_sid.lua", %{"response" => _} -> {200, session(@sid)}
        "/login_sid.lua", _ -> {200, session("0000000000000000")}
        _, %{"switchcmd" => "getdevicelistinfos"} -> {200, body}
      end
    end

    defp device(identifier, children),
      do:
        ~s(<devicelist version="1"><device identifier="#{identifier}" functionbitmask="320" ) <>
          ~s(productname="FRITZ!DECT 301">#{children}</device></devicelist>)

    test "reads every radiator thermostat and skips the other devices" do
      assert {:ok, [living, kitchen], %DectClient{sid: @sid}} =
               DectClient.thermostats(client(device_box(@device_list)))

      assert living == %Thermostat{
               key: "119600123456",
               ain: "11960 0123456",
               name: "Wohnzimmer",
               present: true,
               measured_c: 20.5,
               target: {:heat, 21.0},
               battery_pct: 80,
               battery_low: false,
               busy: false
             }

      assert %Thermostat{
               key: "119600654321",
               name: "Küche",
               measured_c: 17.0,
               target: :off,
               battery_pct: 12,
               battery_low: true
             } = kitchen

      assert_received {:request, "/webservices/homeautoswitch.lua",
                       %{"switchcmd" => "getdevicelistinfos", "sid" => @sid} = params}

      refute Map.has_key?(params, "ain")
    end

    test "254 is the thermostat switched fully on" do
      body = device("1", "<present>1</present><name>Bad</name><hkr><tsoll>254</tsoll></hkr>")

      assert {:ok, [%Thermostat{target: :on}], _} =
               DectClient.thermostats(client(device_box(body)))
    end

    test "without a corrected temperature the measured value is tist, in half degrees" do
      body = device("1", "<present>1</present><name>Bad</name><hkr><tist>39</tist></hkr>")

      assert {:ok, [%Thermostat{measured_c: 19.5}], _} =
               DectClient.thermostats(client(device_box(body)))
    end

    test "an absent thermostat has no readings" do
      body =
        device(
          "11960 0000001",
          "<present>0</present><name>Bad</name><battery></battery><hkr><tist></tist><tsoll></tsoll></hkr>"
        )

      assert {:ok, [thermostat], _} = DectClient.thermostats(client(device_box(body)))

      assert %Thermostat{
               present: false,
               measured_c: nil,
               target: nil,
               battery_pct: nil,
               battery_low: false
             } = thermostat
    end

    test "a command in transit, an open window or a boost makes the target busy" do
      for children <- [
            "<txbusy>1</txbusy><hkr><tsoll>42</tsoll></hkr>",
            "<hkr><tsoll>42</tsoll><windowopenactiv>1</windowopenactiv></hkr>",
            "<hkr><tsoll>254</tsoll><boostactive>1</boostactive></hkr>"
          ] do
        body = device("1", "<present>1</present><name>Bad</name>" <> children)

        assert {:ok, [%Thermostat{busy: true}], _} =
                 DectClient.thermostats(client(device_box(body)))
      end
    end

    test "a device without an identifier is skipped" do
      body =
        ~s(<devicelist><device functionbitmask="320"><present>1</present><name>?</name></device>) <>
          ~s(<device identifier="2" functionbitmask="320"><present>1</present><name>Bad</name></device></devicelist>)

      assert {:ok, [%Thermostat{key: "2"}], _} = DectClient.thermostats(client(device_box(body)))
    end

    test "a broken or foreign answer is no device list" do
      for body <- ["", "<devicelist><device", "not xml", "<other/>", "<?xml?>"] do
        assert {:error, :invalid_device_list, _} =
                 DectClient.thermostats(client(device_box(body)))
      end
    end

    test "an answer that is no device list is an error" do
      assert {:error, :invalid_device_list, %DectClient{sid: @sid}} =
               DectClient.thermostats(client(device_box("<html>oops")))
    end

    test "an HTTP error names the status" do
      routes = fn
        "/login_sid.lua", %{"response" => _} -> {200, session(@sid)}
        "/login_sid.lua", _ -> {200, session("0000000000000000")}
        _, _ -> {500, ""}
      end

      assert {:error, {:http_status, 500}, _} = DectClient.thermostats(client(routes))
    end
  end

  describe "set_target/3" do
    defp target_box(status \\ 200) do
      fn
        "/login_sid.lua", %{"response" => _} -> {200, session(@sid)}
        "/login_sid.lua", _ -> {200, session("0000000000000000")}
        _, %{"switchcmd" => "sethkrtsoll", "param" => param} -> {status, param <> "\n"}
      end
    end

    test "heating sends the temperature in half degrees" do
      assert {:ok, %DectClient{sid: @sid}} =
               DectClient.set_target(client(target_box()), "11960 0123456", {:heat, 21.0})

      assert_received {:request, "/webservices/homeautoswitch.lua",
                       %{
                         "switchcmd" => "sethkrtsoll",
                         "ain" => "11960 0123456",
                         "param" => "42",
                         "sid" => @sid
                       }}

      assert {:ok, _} = DectClient.set_target(client(target_box()), "1", {:heat, 19.5})
      assert_received {:request, _, %{"param" => "39"}}
    end

    test "off sends 253" do
      assert {:ok, _} = DectClient.set_target(client(target_box()), "11960 0123456", :off)
      assert_received {:request, _, %{"switchcmd" => "sethkrtsoll", "param" => "253"}}
    end

    test "an HTTP error names the status" do
      assert {:error, {:http_status, 500}, _} =
               DectClient.set_target(client(target_box(500)), "1", :off)
    end

    defp answering(body) do
      fn
        "/login_sid.lua", %{"response" => _} -> {200, session(@sid)}
        "/login_sid.lua", _ -> {200, session("0000000000000000")}
        _, %{"switchcmd" => "sethkrtsoll"} -> {200, body}
      end
    end

    test "an answer other than the value sent is an error" do
      assert {:error, {:unexpected_response, "inval"}, %DectClient{sid: @sid}} =
               DectClient.set_target(client(answering("inval\n")), "1", :off)

      assert {:error, :blank_response, _} =
               DectClient.set_target(client(answering(" \n")), "1", :off)

      assert {:error, {:unexpected_response, "42"}, _} =
               DectClient.set_target(client(answering("42\n")), "1", :off)
    end

    test "a deadline too close for one request sends nothing" do
      deadline = System.monotonic_time(:millisecond) + 1_999

      assert {:error, :deadline_exceeded, %DectClient{sid: nil}} =
               DectClient.set_target(client(target_box()), "1", :off, deadline: deadline)

      refute_received {:request, _, _}
    end

    defp expiring_box(on_forbidden) do
      fn
        "/login_sid.lua", %{"response" => _} ->
          {200, session("fresh00000000001")}

        "/login_sid.lua", _ ->
          {200, session("0000000000000000")}

        _, %{"sid" => "expired000000000"} ->
          on_forbidden.()
          {403, ""}

        _, %{"switchcmd" => "sethkrtsoll", "param" => param} ->
          {200, param <> "\n"}
      end
    end

    test "after a 403 a deadline too close for the new login sends neither it nor the write" do
      timeout_ms = 2_000
      deadline = System.monotonic_time(:millisecond) + timeout_ms + 20

      run_out = fn ->
        Process.sleep(max(deadline - timeout_ms - System.monotonic_time(:millisecond) + 1, 0))
      end

      client = %{client(expiring_box(run_out)) | sid: "expired000000000"}

      assert {:error, :deadline_exceeded, _client} =
               DectClient.set_target(client, "1", :off, deadline: deadline)

      assert_received {:request, "/webservices/homeautoswitch.lua",
                       %{"sid" => "expired000000000"}}

      refute_received {:request, _, _}
    end

    test "with time to spare a 403 logs in again and writes" do
      deadline = System.monotonic_time(:millisecond) + 60_000
      client = %{client(expiring_box(fn -> :ok end)) | sid: "expired000000000"}

      assert {:ok, %DectClient{sid: "fresh00000000001"}} =
               DectClient.set_target(client, "1", :off, deadline: deadline)

      assert_received {:request, "/webservices/homeautoswitch.lua",
                       %{"sid" => "fresh00000000001", "param" => "253"}}
    end
  end

  test "inspecting a client shows neither the password nor the session" do
    client = %{DectClient.new(host: "fritz.box", user: "u", password: "s3cret") | sid: @sid}
    text = inspect(client)

    refute text =~ "s3cret"
    refute text =~ @sid
    assert text =~ "fritz.box"
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
