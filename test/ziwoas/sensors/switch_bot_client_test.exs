defmodule Ziwoas.Sensors.SwitchBotClientTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Config.Switchbot
  alias Ziwoas.Sensors.SwitchBotClient

  @auth %Switchbot{token: "tok-123", secret: "sec-xyz"}

  defp expect_get(path, status, body) do
    Req.Test.expect(SwitchBotClient, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == path
      Plug.Conn.send_resp(conn, status, body)
    end)
  end

  test "a MeterPro(CO2)'s status, normalised" do
    expect_get("/v1.1/devices/ABC/status", 200, """
    {"statusCode": 100, "message": "success", "body": {"deviceId": "ABC", "deviceType": "MeterPro(CO2)",
     "hubDeviceId": "HUB", "temperature": 21.4, "humidity": 52, "CO2": 612, "battery": 85, "version": "V1.2"}}
    """)

    assert {:ok, data} = SwitchBotClient.device_status(@auth, "ABC")
    assert data.temperature == 21.4
    assert data.humidity == 52
    assert data.co2 == 612
    assert data.battery_pct == 85
    assert data.firmware_version == "V1.2"
    assert data.raw["deviceId"] == "ABC"
  end

  test "an outdoor meter has no CO2" do
    expect_get("/v1.1/devices/OUT/status", 200, """
    {"statusCode": 100, "body": {"deviceType": "WoIOSensor", "temperature": 12.3, "humidity": 71,
     "battery": 100, "version": "V4.2"}}
    """)

    assert {:ok, %{co2: nil, temperature: 12.3, humidity: 71, battery_pct: 100}} =
             SwitchBotClient.device_status(@auth, "OUT")
  end

  test "signs every request with token, time, nonce and HMAC" do
    Req.Test.expect(SwitchBotClient, fn conn ->
      headers = Map.new(conn.req_headers)
      t = headers["t"]
      nonce = headers["nonce"]

      expected =
        :crypto.mac(:hmac, :sha256, "sec-xyz", "tok-123" <> t <> nonce) |> Base.encode64()

      assert headers["authorization"] == "tok-123"
      assert t =~ ~r/\A\d{13}\z/
      assert nonce =~ ~r/\A[0-9a-f-]{36}\z/
      assert headers["sign"] == expected
      Plug.Conn.send_resp(conn, 200, ~s({"statusCode": 100, "body": {}}))
    end)

    assert {:ok, _} = SwitchBotClient.device_status(@auth, "X")
  end

  test "an API status other than 100 is an error with its message" do
    expect_get(
      "/v1.1/devices/X/status",
      200,
      ~s({"statusCode": 161, "message": "device offline", "body": {}})
    )

    assert SwitchBotClient.device_status(@auth, "X") == {:error, "SwitchBot API: device offline"}
  end

  test "without a message the status code names it" do
    expect_get("/v1.1/devices/X/status", 200, ~s({"statusCode": 190}))
    assert SwitchBotClient.device_status(@auth, "X") == {:error, "SwitchBot API: status 190"}
  end

  test "an HTTP error is an error, not retried" do
    expect_get("/v1.1/devices/X/status", 500, "")
    assert SwitchBotClient.device_status(@auth, "X") == {:error, "HTTP 500"}
    Req.Test.verify!(SwitchBotClient)
  end

  test "a transport error is an error" do
    Req.Test.expect(SwitchBotClient, &Req.Test.transport_error(&1, :timeout))
    assert {:error, message} = SwitchBotClient.device_status(@auth, "X")
    assert message =~ "timeout"
  end

  test "lists the meters among the devices" do
    expect_get("/v1.1/devices", 200, """
    {"statusCode": 100, "body": {"deviceList": [
      {"deviceId": "AAA", "deviceName": "Wohnzimmer", "deviceType": "MeterPro(CO2)"},
      {"deviceId": "BBB", "deviceName": "Balkon", "deviceType": "WoIOSensor"},
      {"deviceId": "HUB", "deviceName": "Hub Wohn", "deviceType": "Hub 2"}]}}
    """)

    assert SwitchBotClient.list_sensor_devices(@auth) ==
             {:ok,
              [
                %{id: "AAA", name: "Wohnzimmer", type: :meter_pro_co2},
                %{id: "BBB", name: "Balkon", type: :outdoor_meter}
              ]}
  end

  test "lists all devices" do
    expect_get(
      "/v1.1/devices",
      200,
      ~s({"statusCode": 100, "body": {"deviceList": [{"deviceId": "HUB", "deviceName": "Hub", "deviceType": "Hub 2"}]}})
    )

    assert {:ok, [%{id: "HUB", name: "Hub", device_type: "Hub 2"}]} =
             SwitchBotClient.list_all_devices(@auth)
  end
end
