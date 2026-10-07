defmodule Ziwoas.Govee.BridgeTest do
  # The bridge as a process: bootstrap from the Platform API, LAN replies on the
  # listener, commands, API polls. What it reports to Lights comes to the test.
  use ExUnit.Case, async: true

  alias Ziwoas.Config.Govee
  alias Ziwoas.Govee.Bridge

  @moduletag :capture_log

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

    defaults = [
      name: nil,
      govee: @govee,
      api_req: [plug: api(test)],
      tasks: start_supervised!(Task.Supervisor),
      send: &send(test, {:datagram, &1}),
      put_lamp: &send(test, {:lamp, &1}),
      put_state: &send(test, {:state, &1, &2})
    ]

    start_supervised!({Bridge, Keyword.merge(defaults, opts)})
  end

  defp udp(port, payload) do
    {:ok, socket} = :gen_udp.open(0, [:binary])
    :ok = :gen_udp.send(socket, {127, 0, 0, 1}, port, payload)
    :gen_udp.close(socket)
  end

  defp await(fun, timeout) do
    cond do
      fun.() -> :ok
      timeout <= 0 -> flunk("condition not met")
      true -> Process.sleep(5) && await(fun, timeout - 5)
    end
  end

  defp status(data), do: JSON.encode!(%{"msg" => %{"cmd" => "devStatus", "data" => data}})

  test "bootstrap, LAN replies and commands" do
    bridge = start_bridge!(listen_port: 0)

    assert_receive {:lamp, lamp}, 1_000

    assert lamp == %{
             key: @key,
             sku: "H60B0",
             name: "Uplighter",
             supports_color: true,
             supports_color_temp: true,
             color_temp_min_k: 2700,
             color_temp_max_k: 6500,
             zones: ["rippleLightToggle"],
             scenes: []
           }

    assert_receive {:datagram, %{host: "239.255.255.250", port: 4001}}

    port = Bridge.listen_port(bridge)

    udp(
      port,
      JSON.encode!(%{
        "msg" => %{"cmd" => "scan", "data" => %{"ip" => "127.0.0.1", "device" => @mac}}
      })
    )

    udp(port, status(%{"onOff" => 0, "brightness" => 30}))

    assert_receive {:state, @key, %{on: false, reachable: true, brightness: 30} = reported},
                   1_000

    assert map_size(reported) == 3

    assert Bridge.command(@key, {:brightness, 40}, bridge) == :ok
    assert_received {:state, @key, %{on: true, reachable: true, brightness: 40}}

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

    assert Bridge.command(@key, {:zone, "rippleLightToggle", true}, bridge) == :ok
    assert_receive {:api, "/router/api/v1/device/control", body}, 1_000

    assert body =~
             ~s("capability":{"instance":"rippleLightToggle","type":"devices.capabilities.toggle","value":1})

    assert_receive {:state, @key, %{zone_states: %{"rippleLightToggle" => true}}}, 1_000
  end

  test "an unknown lamp or scene is refused; without a bridge it is unavailable" do
    bridge = start_bridge!(listen_port: false)
    assert_receive {:lamp, _lamp}, 1_000

    assert Bridge.command("NOPE", {:power, true}, bridge) == {:error, :unknown_lamp}
    assert Bridge.command(@key, {:scene, "Disco"}, bridge) == {:error, :unknown_scene}
    assert Bridge.command(@key, {:power, true}, :no_bridge) == {:error, :unavailable}
    refute_received {:state, _, _}
  end

  test "a failing API control records nothing" do
    test = self()

    failing = fn conn ->
      if conn.request_path == "/router/api/v1/device/control",
        do: Plug.Conn.send_resp(conn, 200, ~s({"code":429,"message":"too many"})),
        else: api(test).(conn)
    end

    bridge = start_bridge!(listen_port: false, api_req: [plug: failing])
    assert_receive {:lamp, _lamp}, 1_000

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert Bridge.command(@key, {:power, true}, bridge) == :ok
        await(fn -> :sys.get_state(bridge).pending == %{} end, 1_000)
      end)

    assert log =~ ~s({:api, 429, "too many"})
    refute_received {:state, _, _}
  end

  test "an API poll reports the cloud's state" do
    bridge = start_bridge!(listen_port: false)
    assert_receive {:lamp, _lamp}, 1_000

    send(bridge, :api_poll)

    assert_receive {:state, @key, %{on: true, reachable: true, brightness: 70}}, 1_000
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
        listen_port: false,
        api_req: [plug: exiting],
        govee: %{@govee | api_poll_seconds: 1}
      )

    assert_receive {:lamp, _lamp}, 1_000

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert_receive :state_requested, 2_500
        assert_receive :state_requested, 2_500
        :sys.get_state(bridge)
      end)

    assert log =~ "Govee bridge: API poll failed: {:exit, :boom}"
    assert Process.alive?(bridge)
  end

  test "a LAN port held elsewhere is retried until it binds" do
    {:ok, blocker} = :gen_udp.open(0, [:binary, ip: {0, 0, 0, 0}])
    {:ok, port} = :inet.port(blocker)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        bridge = start_bridge!(listen_port: port)
        assert Bridge.listen_port(bridge) == nil

        :gen_udp.close(blocker)
        await(fn -> Bridge.listen_port(bridge) == port end, 3_000)
      end)

    assert log =~ "Govee bridge listener: :eaddrinuse; retrying in 1000 ms"
  end
end
