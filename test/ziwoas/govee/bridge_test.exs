defmodule Ziwoas.Govee.BridgeTest do
  # test/govees/bridge_test.rb as a process: bootstrap from the Platform API, LAN
  # replies on the listener, set verbs, and what a shadow bridge leaves alone.
  use ExUnit.Case, async: true

  alias Ziwoas.Config.Govee
  alias Ziwoas.Govee.Bridge
  alias Ziwoas.Ownership

  @moduletag :capture_log

  setup do
    on_exit(&Ownership.clear_override/0)
    :ok
  end

  @mac "14:AB:DB:48:44:06:4B:60"
  @key "14ABDB4844064B60"
  @govee %Govee{
    api_key: "k",
    lan_poll_seconds: 3600,
    api_poll_seconds: 3600,
    pending_window_seconds: 5,
    names: %{}
  }

  @devices JSON.encode!(%{
             "code" => 200,
             "data" => [
               %{
                 "sku" => "H60B0",
                 "device" => @mac,
                 "deviceName" => "Uplighter",
                 "capabilities" => [
                   %{"instance" => "colorRgb"},
                   %{"instance" => "rippleLightToggle"},
                   %{
                     "instance" => "colorTemperatureK",
                     "parameters" => %{"range" => %{"min" => 2700, "max" => 6500}}
                   }
                 ]
               }
             ]
           })

  # The Platform API as a plug: devices, no scenes, a state; control calls are reported.
  defp api(test) do
    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:api, conn.request_path, body})

      response =
        case conn.request_path do
          "/router/api/v1/user/devices" ->
            @devices

          "/router/api/v1/device/scenes" ->
            ~s({"code":200,"payload":{"capabilities":[]}})

          "/router/api/v1/device/state" ->
            ~s({"code":200,"payload":{"capabilities":[{"instance":"powerSwitch","state":{"value":1}},{"instance":"brightness","state":{"value":70}}]}})

          "/router/api/v1/device/control" ->
            ~s({"code":200,"msg":"success"})
        end

      Plug.Conn.send_resp(conn, 200, response)
    end
  end

  defp start_bridge!(opts) do
    test = self()
    if opts[:owner], do: Ownership.override(%{govee_bridge: :phoenix})

    defaults = [
      name: nil,
      govee: @govee,
      api_req: [plug: api(test)],
      send: &send(test, {:datagram, &1}),
      publish: fn topic, payload ->
        send(test, {:published, topic, payload})
        :ok
      end
    ]

    start_supervised!({Bridge, Keyword.merge(defaults, opts)})
  end

  defp udp(port, payload) do
    {:ok, socket} = :gen_udp.open(0, [:binary])
    :ok = :gen_udp.send(socket, {127, 0, 0, 1}, port, payload)
    :gen_udp.close(socket)
  end

  defp await(fun, timeout \\ 1_000) do
    cond do
      fun.() -> :ok
      timeout <= 0 -> flunk("condition not met")
      true -> Process.sleep(5) && await(fun, timeout - 5)
    end
  end

  defp status(data), do: JSON.encode!(%{"msg" => %{"cmd" => "devStatus", "data" => data}})

  test "as owner: bootstrap, LAN replies and a set verb" do
    bridge = start_bridge!(owner: true, listen_port: 0)

    assert_receive {:published, "govees/" <> @key <> "/config", config}, 1_000

    assert config ==
             ~s({"sku":"H60B0","name":"Uplighter","supports_color":true,"supports_color_temp":true,) <>
               ~s("color_temp_min_k":2700,"color_temp_max_k":6500,"zones":["rippleLightToggle"],"scenes":[]})

    assert_receive {:datagram, %{host: "239.255.255.250", port: 4001}}

    port = Bridge.listen_port(bridge)

    udp(
      port,
      JSON.encode!(%{
        "msg" => %{"cmd" => "scan", "data" => %{"ip" => "127.0.0.1", "device" => @mac}}
      })
    )

    udp(port, status(%{"onOff" => 0, "brightness" => 30}))

    assert_receive {:published, "govees/" <> @key <> "/state",
                    ~s({"on":false,"reachable":true,"brightness":30})},
                   1_000

    send(bridge, {:set, @key, ~s({"brightness":40})})

    assert_receive {:published, "govees/" <> @key <> "/state",
                    ~s({"on":true,"reachable":true,"brightness":40})},
                   1_000

    assert_received {:datagram,
                     %{
                       host: "127.0.0.1",
                       port: 4003,
                       data: ~s({"msg":{"cmd":"brightness","data":{"value":40}}})
                     }}

    assert_received {:datagram,
                     %{
                       host: "127.0.0.1",
                       port: 4003,
                       data: ~s({"msg":{"cmd":"devStatus","data":{}}})
                     }}

    send(bridge, {:set, @key, ~s({"zone":{"name":"rippleLightToggle","on":true}})})
    assert_receive {:api, "/router/api/v1/device/control", body}, 1_000

    assert body =~
             ~s("capability":{"type":"devices.capabilities.toggle","instance":"rippleLightToggle","value":1})
  end

  test "as owner a failing API control publishes nothing" do
    test = self()

    failing = fn conn ->
      if conn.request_path == "/router/api/v1/device/control",
        do: Plug.Conn.send_resp(conn, 200, ~s({"code":429,"message":"too many"})),
        else: api(test).(conn)
    end

    bridge = start_bridge!(owner: true, listen_port: false, api_req: [plug: failing])
    assert_receive {:published, _config_topic, _}, 1_000

    send(bridge, {:set, @key, ~s({"power":"on"})})
    :sys.get_state(bridge)
    refute_received {:published, _, _}
  end

  test "an API poll publishes the cloud's state" do
    bridge = start_bridge!(owner: true, listen_port: false)
    assert_receive {:published, _config_topic, _}, 1_000

    send(bridge, :api_poll)

    assert_receive {:published, "govees/" <> @key <> "/state",
                    ~s({"on":true,"reachable":true,"brightness":70})},
                   1_000
  end

  test "an API poll whose task exits is logged and the next poll still comes" do
    test = self()

    exiting = fn conn ->
      if conn.request_path == "/router/api/v1/device/state" do
        send(test, :state_requested)
        exit(:boom)
      else
        api(test).(conn)
      end
    end

    bridge =
      start_bridge!(
        owner: true,
        listen_port: false,
        api_req: [plug: exiting],
        govee: %{@govee | api_poll_seconds: 1}
      )

    assert_receive {:published, _config_topic, _}, 1_000

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert_receive :state_requested, 2_500
        assert_receive :state_requested, 2_500
        :sys.get_state(bridge)
      end)

    assert log =~ "Govee bridge: API poll failed: exit: :boom"
    assert Process.alive?(bridge)
  end

  test "as owner a LAN port held elsewhere is retried until it binds" do
    {:ok, blocker} = :gen_udp.open(0, [:binary, ip: {0, 0, 0, 0}])
    {:ok, port} = :inet.port(blocker)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        bridge = start_bridge!(owner: true, listen_port: port)
        assert Bridge.listen_port(bridge) == nil

        :gen_udp.close(blocker)
        await(fn -> Bridge.listen_port(bridge) == port end, 3_000)
      end)

    assert log =~ "Govee bridge listener: :eaddrinuse; retrying in 1000 ms"
  end

  test "in shadow mode: no LAN port, no datagram, no command, only API reads" do
    test = self()

    bridge =
      start_supervised!(
        {Bridge,
         name: nil,
         govee: @govee,
         api_req: [plug: api(test)],
         send: &send(test, {:datagram, &1}),
         owner: false}
      )

    assert_receive {:api, "/router/api/v1/user/devices", _}, 1_000
    await(fn -> :sys.get_state(bridge).bootstrapped end)
    send(bridge, :api_poll)
    assert_receive {:api, "/router/api/v1/device/state", _}, 1_000
    send(bridge, :lan_poll)
    send(bridge, {:set, @key, ~s({"power":"on"})})
    :sys.get_state(bridge)

    assert Bridge.listen_port(bridge) == nil
    refute_received {:datagram, _}
    refute_received {:api, "/router/api/v1/device/control", _}
    assert Process.alive?(bridge)
  end
end
