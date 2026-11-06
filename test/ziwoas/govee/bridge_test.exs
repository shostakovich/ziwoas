defmodule Ziwoas.Govee.BridgeTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Config.Govee
  alias Ziwoas.Govee.{Bridge, DeviceRegistry}
  alias Ziwoas.Lights.Light

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

  defp devices(capabilities), do: listing([{@mac, capabilities}])

  defp listing(lamps),
    do:
      JSON.encode!(%{
        "code" => 200,
        "data" =>
          for {mac, capabilities} <- lamps do
            %{
              "sku" => "H60B0",
              "device" => mac,
              "deviceName" => "Uplighter",
              "capabilities" => capabilities
            }
          end
      })

  @colour [
    %{"instance" => "colorRgb"},
    %{
      "instance" => "colorTemperatureK",
      "parameters" => %{"range" => %{"min" => 2700, "max" => 6500}}
    }
  ]

  @zones [%{"instance" => "rippleLightToggle"} | @colour]

  defp zone_lamp, do: devices(@zones)
  defp plain_lamp, do: devices(@colour)

  defp cloud(values) do
    capabilities =
      for {instance, value} <- values,
          do: %{"instance" => instance, "state" => %{"value" => value}}

    JSON.encode!(%{"code" => 200, "payload" => %{"capabilities" => capabilities}})
  end

  defp cloud_on, do: cloud(%{"powerSwitch" => 1, "brightness" => 70})

  defp answered_by_test(test) do
    fn ->
      send(test, {:asked, self()})

      receive do
        {:answer, body} -> body
      end
    end
  end

  defp api(test, opts \\ []) do
    devices = Keyword.get_lazy(opts, :devices, &zone_lamp/0)
    state = Keyword.get(opts, :state, &cloud_on/0)

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:api, conn.request_path, body})

      response =
        case conn.request_path do
          "/router/api/v1/user/devices" -> devices
          "/router/api/v1/device/scenes" -> ~s({"code":200,"payload":{"capabilities":[]}})
          "/router/api/v1/device/state" -> state.()
          "/router/api/v1/device/control" -> ~s({"code":200,"msg":"success"})
        end

      Plug.Conn.send_resp(conn, 200, response)
    end
  end

  defp start_bridge!(opts) do
    test = self()
    {cloud, opts} = Keyword.pop(opts, :cloud, [])

    defaults = [
      name: nil,
      govee: @govee,
      api_req: [plug: api(test, cloud)],
      tasks: start_supervised!(Task.Supervisor),
      send: &send(test, {:datagram, &1}),
      put_lamp: &send(test, {:lamp, &1}),
      put_state: &send(test, {:state, &1, &2}),
      stored_lamps: fn -> [] end
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

  defp from(bridge, ip, payload),
    do: send(bridge, {:udp, :sys.get_state(bridge).socket, ip, 4003, payload})

  defp heard_at!(bridge, mac, ip) do
    scan = %{"ip" => ip |> :inet.ntoa() |> List.to_string(), "device" => mac}
    from(bridge, ip, JSON.encode!(%{"msg" => %{"cmd" => "scan", "data" => scan}}))
    from(bridge, ip, status(%{"onOff" => 1}))
  end

  defp asked_for(body), do: JSON.decode!(body)["payload"]["device"]

  test "a lamp the cloud lists is stored, heard on the LAN and commanded" do
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

  describe "hearing a lamp" do
    defp scan(port),
      do:
        udp(
          port,
          JSON.encode!(%{
            "msg" => %{"cmd" => "scan", "data" => %{"ip" => "127.0.0.1", "device" => @mac}}
          })
        )

    defp flush_datagrams do
      receive do
        {:datagram, _datagram} -> flush_datagrams()
      after
        50 -> :ok
      end
    end

    test "a lamp never heard is not silent; heard, it falls silent after three LAN polls" do
      now = start_supervised!({Agent, fn -> 0 end})

      bridge =
        start_bridge!(
          listen_port: 0,
          govee: %{@govee | lan_poll_seconds: 8},
          clock: fn -> Agent.get(now, & &1) end
        )

      assert_receive {:lamp, _lamp}, 1_000
      refute Bridge.silent?(@key, bridge)

      scan(Bridge.listen_port(bridge))
      await(fn -> :sys.get_state(bridge).heard_at[@key] == 0 end, 1_000)

      Agent.update(now, fn _ -> 24 end)
      refute Bridge.silent?(@key, bridge)

      Agent.update(now, fn _ -> 25 end)
      assert Bridge.silent?(@key, bridge)

      udp(Bridge.listen_port(bridge), status(%{"onOff" => 1}))
      await(fn -> not Bridge.silent?(@key, bridge) end, 1_000)
    end

    test "a watcher hears of every reply, and the bridge scans fast while it watches" do
      bridge = start_bridge!(listen_port: 0, watch_poll_ms: 10)
      assert_receive {:lamp, _lamp}, 1_000
      port = Bridge.listen_port(bridge)
      scan(port)
      await(fn -> :sys.get_state(bridge).heard_at[@key] end, 1_000)
      flush_datagrams()

      assert Bridge.watch(@key, bridge) == :ok

      for _poll <- 1..2 do
        assert_receive {:datagram, %{host: "239.255.255.250", port: 4001}}, 1_000

        assert_receive {:datagram,
                        %{host: "127.0.0.1", data: ~s({"msg":{"cmd":"devStatus","data":{}}})}}
      end

      scan(port)
      assert_receive {:lamp_heard, @key, nil}, 1_000

      udp(port, status(%{"onOff" => 1, "brightness" => 30}))
      assert_receive {:lamp_heard, @key, %{on: true, brightness: 30}}, 1_000

      assert Bridge.unwatch(@key, bridge) == :ok
      flush_datagrams()
      refute_receive {:datagram, _datagram}, 100

      scan(port)
      refute_receive {:lamp_heard, _key, _telemetry}, 100

      assert Bridge.watch(@key, bridge) == :ok
      assert_receive {:datagram, %{host: "239.255.255.250", port: 4001}}, 1_000
    end

    test "a scan reply from an unknown device is not remembered" do
      bridge = start_bridge!(listen_port: 0)
      assert_receive {:lamp, _lamp}, 1_000

      udp(
        Bridge.listen_port(bridge),
        JSON.encode!(%{
          "msg" => %{"cmd" => "scan", "data" => %{"ip" => "127.0.0.9", "device" => "AA:BB"}}
        })
      )

      scan(Bridge.listen_port(bridge))
      await(fn -> :sys.get_state(bridge).heard_at[@key] end, 1_000)
      assert Map.keys(:sys.get_state(bridge).heard_at) == [@key]
    end

    test "a watcher that goes away ends its watch" do
      bridge = start_bridge!(listen_port: false, watch_poll_ms: 10)
      assert_receive {:lamp, _lamp}, 1_000

      watcher = spawn(fn -> Process.sleep(:infinity) end)
      assert Bridge.watch(@key, bridge, watcher) == :ok
      Process.exit(watcher, :kill)

      await(fn -> :sys.get_state(bridge).watchers == %{} end, 1_000)
    end

    test "without a bridge nothing is silent and nothing can be watched" do
      refute Bridge.silent?(@key, :no_bridge)
      assert Bridge.watch(@key, :no_bridge) == {:error, :unavailable}
      assert Bridge.unwatch(@key, :no_bridge) == :ok
    end
  end

  test "an unknown lamp or scene is refused; without a bridge it is unavailable" do
    bridge = start_bridge!(listen_port: false)
    assert_receive {:lamp, _lamp}, 1_000

    assert Bridge.command("NOPE", {:power, true}, bridge) == {:error, :unknown_lamp}
    assert Bridge.command(@key, {:scene, "Disco"}, bridge) == {:error, :unknown_scene}
    assert Bridge.command(@key, {:power, true}, :no_bridge) == {:error, :unavailable}
    refute_received {:state, _, _}
  end

  test "a bridge that does not answer in time is unavailable" do
    busy = spawn_link(fn -> Process.sleep(:infinity) end)
    assert Bridge.command(@key, {:power, true}, busy) == {:error, :unavailable}
  end

  test "a state Lights does not store is logged and the bridge runs on" do
    test = self()

    put_state = fn key, _state ->
      send(test, {:refused, key})
      {:error, :busy}
    end

    bridge = start_bridge!(listen_port: false, put_state: put_state)
    assert_receive {:lamp, _lamp}, 1_000

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert Bridge.command(@key, {:power, true}, bridge) == :ok
        assert_receive {:refused, @key}, 1_000
        await(fn -> :sys.get_state(bridge).pending == %{} end, 1_000)
      end)

    assert log =~ "state of #{@key} not stored: :busy"
    assert Process.alive?(bridge)
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

  describe "the lamp's LAN reply wins over the cloud" do
    defp heard_lamp!(opts) do
      bridge = start_bridge!([listen_port: 0] ++ opts)
      assert_receive {:lamp, _lamp}, 1_000
      port = Bridge.listen_port(bridge)
      scan(port)
      await(fn -> :sys.get_state(bridge).heard_at[@key] end, 1_000)
      {bridge, port}
    end

    defp settled(bridge), do: await(fn -> :sys.get_state(bridge).pending == %{} end, 1_000)

    test "a lamp heard on the LAN shows its change at once, without asking the cloud" do
      {_bridge, port} = heard_lamp!(cloud: [devices: plain_lamp()])

      udp(port, status(%{"onOff" => 0, "brightness" => 30}))
      assert_receive {:state, @key, %{on: false, reachable: true, brightness: 30}}, 1_000

      udp(port, status(%{"onOff" => 1, "brightness" => 55}))
      assert_receive {:state, @key, %{on: true, reachable: true, brightness: 55}}, 1_000

      refute_receive {:api, "/router/api/v1/device/state", _body}, 100
    end

    test "a LAN reply in colour clears the colour temperature" do
      {_bridge, port} = heard_lamp!(cloud: [devices: plain_lamp()])

      udp(port, status(%{"onOff" => 1, "colorTemInKelvin" => 2700}))
      assert_receive {:state, @key, %{color_temp_k: 2700}}, 1_000

      udp(
        port,
        status(%{
          "onOff" => 1,
          "colorTemInKelvin" => 0,
          "color" => %{"r" => 255, "g" => 0, "b" => 0}
        })
      )

      assert_receive {:state, @key, %{color: %{r: 255, g: 0, b: 0}, color_temp_k: nil}}, 1_000
    end

    test "a colour command clears the colour temperature" do
      {bridge, _port} = heard_lamp!(cloud: [devices: plain_lamp()])

      assert Bridge.command(@key, {:color_temp, 3000}, bridge) == :ok
      assert_receive {:state, @key, %{color_temp_k: 3000}}, 1_000

      assert Bridge.command(@key, {:color, %{r: 0, g: 0, b: 255}}, bridge) == :ok
      assert_receive {:state, @key, %{color: %{r: 0, g: 0, b: 255}, color_temp_k: nil}}, 1_000
    end

    test "while the LAN and the cloud keep disagreeing, LAN readings do not ask again" do
      {bridge, port} = heard_lamp!([])
      assert Bridge.watch(@key, bridge) == :ok
      reading = status(%{"onOff" => 1, "brightness" => 30})

      udp(port, reading)
      assert_receive {:state, @key, %{on: true, brightness: 30}}, 1_000
      assert_receive {:api, "/router/api/v1/device/state", _body}, 1_000
      assert_receive {:lamp_heard, @key, %{brightness: 30}}, 1_000
      settled(bridge)

      for _reading <- 1..3 do
        udp(port, reading)
        assert_receive {:lamp_heard, @key, %{brightness: 30}}, 1_000
      end

      settled(bridge)
      refute_receive {:api, "/router/api/v1/device/state", _body}, 100
      refute_received {:state, @key, %{brightness: 70}}
    end

    test "a zone lamp has one cloud request in flight at a time" do
      {bridge, port} = heard_lamp!(cloud: [state: answered_by_test(self())])
      assert Bridge.watch(@key, bridge) == :ok

      udp(port, status(%{"onOff" => 1, "brightness" => 30}))
      assert_receive {:asked, asker}, 1_000

      udp(port, status(%{"onOff" => 1, "brightness" => 40}))
      assert_receive {:lamp_heard, @key, %{brightness: 40}}, 1_000
      :sys.get_state(bridge)
      refute_receive {:asked, _asker}, 100

      send(asker, {:answer, cloud(%{})})
      settled(bridge)

      udp(port, status(%{"onOff" => 1, "brightness" => 50}))
      assert_receive {:asked, _asker}, 1_000
    end

    test "a zone lamp whose LAN reply changes takes its zone states from the cloud" do
      zone = start_supervised!({Agent, fn -> 0 end})

      ripple = fn ->
        cloud(%{
          "powerSwitch" => 1,
          "brightness" => 70,
          "rippleLightToggle" => Agent.get(zone, & &1)
        })
      end

      {_bridge, port} = heard_lamp!(cloud: [state: ripple])

      udp(port, status(%{"onOff" => 1, "brightness" => 30}))

      assert_receive {:state, @key,
                      %{brightness: 30, zone_states: %{"rippleLightToggle" => false}}},
                     1_000

      Agent.update(zone, fn _ -> 1 end)
      udp(port, status(%{"onOff" => 1, "brightness" => 40}))

      assert_receive {:state, @key,
                      %{brightness: 40, zone_states: %{"rippleLightToggle" => true}}},
                     1_000
    end

    test "a cloud answer of offline leaves a lamp heard on the LAN on and reachable" do
      offline = fn -> cloud(%{"online" => false, "powerSwitch" => 0}) end
      {bridge, port} = heard_lamp!(cloud: [state: offline])

      udp(port, status(%{"onOff" => 1, "brightness" => 30}))
      assert_receive {:state, @key, %{on: true, reachable: true, brightness: 30}}, 1_000

      send(bridge, :api_poll)
      :sys.get_state(bridge)
      settled(bridge)

      refute_received {:state, @key, %{on: false}}
      refute_received {:state, @key, %{reachable: false}}
    end

    test "a lamp gone silent on the LAN takes its full state from the poll" do
      now = start_supervised!({Agent, fn -> 0 end})
      offline = fn -> cloud(%{"online" => false, "powerSwitch" => 0}) end

      {bridge, port} =
        heard_lamp!(
          govee: %{@govee | lan_poll_seconds: 8},
          clock: fn -> Agent.get(now, & &1) end,
          cloud: [devices: plain_lamp(), state: offline]
        )

      udp(port, status(%{"onOff" => 1, "brightness" => 30}))
      assert_receive {:state, @key, %{on: true, reachable: true}}, 1_000

      Agent.update(now, fn _ -> 25 end)
      send(bridge, :api_poll)

      assert_receive {:state, @key, %{on: false, reachable: false}}, 1_000
    end

    test "the poll asks nothing for a plain lamp heard on the LAN" do
      plain = "14:AB:DB:48:44:06:4B:61"
      never_heard = "14:AB:DB:48:44:06:4B:62"

      bridge =
        start_bridge!(
          listen_port: 0,
          cloud: [devices: listing([{@mac, @zones}, {plain, @colour}, {never_heard, @colour}])]
        )

      for _lamp <- 1..3, do: assert_receive({:lamp, _lamp}, 1_000)
      heard_at!(bridge, @mac, {10, 0, 0, 1})
      heard_at!(bridge, plain, {10, 0, 0, 2})
      assert_receive {:api, "/router/api/v1/device/state", body}, 1_000
      assert asked_for(body) == @mac
      settled(bridge)

      send(bridge, :api_poll)
      assert_receive {:api, "/router/api/v1/device/state", first}, 1_000
      assert_receive {:api, "/router/api/v1/device/state", second}, 1_000
      settled(bridge)

      assert Enum.sort([asked_for(first), asked_for(second)]) == [@mac, never_heard]
      refute_received {:api, "/router/api/v1/device/state", _body}
    end

    test "a lamp seen only by a scan takes its full state from the poll" do
      {bridge, _port} = heard_lamp!(cloud: [devices: plain_lamp()])

      send(bridge, :api_poll)

      assert_receive {:state, @key, %{on: true, reachable: true, brightness: 70}}, 1_000
    end

    test "an API poll reports the full state of a lamp never heard on the LAN" do
      bridge = start_bridge!(listen_port: false)
      assert_receive {:lamp, _lamp}, 1_000

      send(bridge, :api_poll)

      assert_receive {:state, @key, %{on: true, reachable: true, brightness: 70}}, 1_000
    end

    test "a polled answer requested before a command does not undo it" do
      now = start_supervised!({Agent, fn -> 0 end})

      bridge =
        start_bridge!(
          listen_port: false,
          clock: fn -> Agent.get(now, & &1) end,
          cloud: [state: answered_by_test(self())]
        )

      assert_receive {:lamp, _lamp}, 1_000
      send(bridge, :api_poll)
      assert_receive {:asked, asker}, 1_000

      assert Bridge.command(@key, {:power, false}, bridge) == :ok
      assert_receive {:state, @key, %{on: false}}, 1_000

      Agent.update(now, fn _ -> 60 end)
      send(asker, {:answer, cloud_on()})
      settled(bridge)

      refute_received {:state, @key, %{on: true}}
    end

    test "a polled answer requested between two commands does not undo the second" do
      now = start_supervised!({Agent, fn -> 0 end})

      bridge =
        start_bridge!(
          listen_port: false,
          clock: fn -> Agent.get(now, & &1) end,
          cloud: [state: answered_by_test(self())]
        )

      assert_receive {:lamp, _lamp}, 1_000
      assert Bridge.command(@key, {:power, true}, bridge) == :ok
      assert_receive {:state, @key, %{on: true}}, 1_000
      settled(bridge)

      send(bridge, :api_poll)
      assert_receive {:asked, asker}, 1_000

      assert Bridge.command(@key, {:power, false}, bridge) == :ok
      assert_receive {:state, @key, %{on: false}}, 1_000

      Agent.update(now, fn _ -> 60 end)
      send(asker, {:answer, cloud_on()})
      settled(bridge)

      refute_received {:state, @key, %{on: true}}
    end

    test "a command to one lamp does not discard the polled answer for another" do
      other_mac = "14:AB:DB:48:44:06:4B:61"
      other_key = "14ABDB4844064B61"

      bridge =
        start_bridge!(
          listen_port: false,
          cloud: [
            devices: listing([{@mac, @colour}, {other_mac, @colour}]),
            state: answered_by_test(self())
          ]
        )

      for _lamp <- 1..2, do: assert_receive({:lamp, _lamp}, 1_000)
      send(bridge, :api_poll)
      assert_receive {:asked, asker}, 1_000

      assert Bridge.command(@key, {:power, false}, bridge) == :ok
      assert_receive {:state, @key, %{on: false}}, 1_000

      send(asker, {:answer, cloud_on()})
      assert_receive {:asked, asker}, 1_000
      send(asker, {:answer, cloud_on()})

      assert_receive {:state, ^other_key, %{on: true, brightness: 70}}, 1_000
      settled(bridge)
      refute_received {:state, @key, %{on: true}}
    end

    test "zone states asked for before a command do not undo it" do
      now = start_supervised!({Agent, fn -> 0 end})

      {bridge, port} =
        heard_lamp!(
          clock: fn -> Agent.get(now, & &1) end,
          cloud: [state: answered_by_test(self())]
        )

      udp(port, status(%{"onOff" => 1, "brightness" => 30}))
      assert_receive {:asked, asker}, 1_000

      assert Bridge.command(@key, {:zone, "rippleLightToggle", true}, bridge) == :ok
      assert_receive {:state, @key, %{zone_states: %{"rippleLightToggle" => true}}}, 1_000

      Agent.update(now, fn _ -> 60 end)
      send(asker, {:answer, cloud(%{"powerSwitch" => 1, "rippleLightToggle" => 0})})
      settled(bridge)

      refute_received {:state, @key, %{zone_states: %{"rippleLightToggle" => false}}}
    end

    test "zone states the cloud lags behind on do not undo a zone command in its window" do
      stale = fn -> cloud(%{"powerSwitch" => 1, "rippleLightToggle" => 0}) end
      {bridge, port} = heard_lamp!(clock: fn -> 0 end, cloud: [state: stale])

      udp(port, status(%{"onOff" => 1, "brightness" => 30}))
      assert_receive {:api, "/router/api/v1/device/state", _body}, 1_000
      assert_receive {:state, @key, %{zone_states: %{"rippleLightToggle" => false}}}, 1_000
      settled(bridge)

      assert Bridge.command(@key, {:zone, "rippleLightToggle", true}, bridge) == :ok
      assert_receive {:state, @key, %{zone_states: %{"rippleLightToggle" => true}}}, 1_000
      settled(bridge)

      udp(port, status(%{"onOff" => 1, "brightness" => 40}))
      assert_receive {:api, "/router/api/v1/device/state", _body}, 1_000
      settled(bridge)

      refute_received {:state, @key, %{zone_states: %{"rippleLightToggle" => false}}}
    end
  end

  describe "while the cloud does not list the lamps" do
    defp stored_lamp,
      do: %Light{
        key: @key,
        name: "Uplighter",
        sku: "H60B0",
        supports_color: true,
        supports_color_temp: true,
        color_temp_min_k: 2700,
        color_temp_max_k: 6500,
        zones: ["rippleLightToggle"],
        firmware_scenes: ["Forest"]
      }

    @forest ~s({"code":200,"payload":{"capabilities":[{"parameters":{"options":[{"name":"Forest","value":{"id":7,"paramId":70}}]}}]}})

    defp cloud_listing(test, listed?) do
      fn conn ->
        case conn.request_path do
          "/router/api/v1/user/devices" -> device_list(conn, test, listed?.())
          "/router/api/v1/device/scenes" -> Plug.Conn.send_resp(conn, 200, @forest)
          _path -> api(test).(conn)
        end
      end
    end

    defp device_list(conn, test, true), do: api(test).(conn)
    defp device_list(conn, test, :empty), do: api(test, devices: listing([])).(conn)
    defp device_list(conn, _test, :timeout), do: Req.Test.transport_error(conn, :timeout)

    defp device_list(conn, _test, false),
      do: Plug.Conn.send_resp(conn, 200, ~s({"code":500,"message":"down"}))

    defp unlisted_bridge!(opts) do
      listing = Keyword.get(opts, :listing, fn -> false end)

      start_bridge!(
        Keyword.merge(
          [
            listen_port: 0,
            stored_lamps: fn -> [stored_lamp()] end,
            api_req: [plug: cloud_listing(self(), listing)]
          ],
          opts
        )
      )
    end

    defp registered(bridge), do: DeviceRegistry.find(:sys.get_state(bridge).registry, @key)

    test "a stored lamp is heard and switched on the LAN while the device list times out" do
      bridge = unlisted_bridge!(listing: fn -> :timeout end)
      port = Bridge.listen_port(bridge)

      scan(port)
      udp(port, status(%{"onOff" => 0, "brightness" => 30}))
      assert_receive {:state, @key, %{on: false, reachable: true, brightness: 30}}, 1_000

      assert Bridge.command(@key, {:power, true}, bridge) == :ok

      assert_received {:datagram,
                       %{host: "127.0.0.1", data: ~s({"msg":{"cmd":"turn","data":{"value":1}}})}}

      refute_received {:lamp, _lamp}
    end

    test "a device list that fails is retried; it brings cloud id and scenes and keeps the IP" do
      listed = start_supervised!({Agent, fn -> false end})

      bridge =
        unlisted_bridge!(
          govee: %{@govee | api_poll_seconds: 1},
          listing: fn -> Agent.get(listed, & &1) end,
          stored_lamps: fn -> [stored_lamp(), %Light{key: "GONE", name: "Weg"}] end
        )

      scan(Bridge.listen_port(bridge))
      await(fn -> registered(bridge).ip == "127.0.0.1" end, 1_000)
      Agent.update(listed, fn _ -> true end)

      assert_receive {:lamp, %{key: @key, scenes: ["Forest"]}}, 2_500
      :sys.get_state(bridge)
      refute_received {:lamp, _unlisted}
      assert %{api_id: @mac, ip: "127.0.0.1"} = registered(bridge)

      assert Bridge.command(@key, {:zone, "rippleLightToggle", true}, bridge) == :ok
      assert_receive {:api, "/router/api/v1/device/control", zone}, 1_000
      assert asked_for(zone) == @mac

      assert Bridge.command(@key, {:scene, "Forest"}, bridge) == :ok
      assert_receive {:api, "/router/api/v1/device/control", scene}, 1_000
      assert scene =~ ~s("value":{"id":7,"paramId":70})

      assert_received {:api, "/router/api/v1/user/devices", _list}
      refute_receive {:api, "/router/api/v1/user/devices", _again}, 1_500
    end

    test "a device list that fails is logged once" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          bridge = unlisted_bridge!(listen_port: false)
          :sys.get_state(bridge)
          settled(bridge)
        end)

      assert [_once] = Regex.scan(~r/cloud device list/, log)
    end

    test "a device list that lists no lamps is retried" do
      listed = start_supervised!({Agent, fn -> :empty end})

      unlisted_bridge!(
        govee: %{@govee | api_poll_seconds: 1},
        listing: fn -> Agent.get(listed, & &1) end
      )

      assert_receive {:api, "/router/api/v1/user/devices", _empty}, 1_000
      Agent.update(listed, fn _ -> true end)

      assert_receive {:lamp, %{key: @key}}, 2_500
    end

    test "the cloud's list scans the LAN again" do
      listed = start_supervised!({Agent, fn -> false end})

      bridge =
        unlisted_bridge!(listen_port: false, listing: fn -> Agent.get(listed, & &1) end)

      assert_receive {:datagram, %{host: "239.255.255.250", port: 4001}}, 1_000
      :sys.get_state(bridge)
      settled(bridge)

      Agent.update(listed, fn _ -> true end)
      send(bridge, :list_cloud_devices)

      assert_receive {:lamp, %{key: @key}}, 1_000
      assert_received {:datagram, %{host: "239.255.255.250", port: 4001}}
    end

    test "a zone lamp heard before the cloud lists it asks for its zones on its next reply" do
      listed = start_supervised!({Agent, fn -> false end})
      bridge = unlisted_bridge!(listing: fn -> Agent.get(listed, & &1) end)
      port = Bridge.listen_port(bridge)
      reading = status(%{"onOff" => 1, "brightness" => 30})

      scan(port)
      udp(port, reading)
      assert_receive {:state, @key, %{brightness: 30}}, 1_000

      Agent.update(listed, fn _ -> true end)
      send(bridge, :list_cloud_devices)
      assert_receive {:lamp, %{key: @key}}, 1_000

      udp(port, reading)
      assert_receive {:api, "/router/api/v1/device/state", body}, 1_000
      assert asked_for(body) == @mac
    end

    test "stored lamps that cannot be read leave the bridge to the cloud's list" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          bridge =
            start_bridge!(listen_port: false, stored_lamps: fn -> raise "database is locked" end)

          assert_receive {:lamp, %{key: @key}}, 1_000
          assert registered(bridge).api_id == @mac
        end)

      assert log =~ "database is locked"
    end

    test "a cloud-only command for a stored lamp is unavailable and asks no cloud" do
      bridge = unlisted_bridge!([])

      assert Bridge.command(@key, {:power, true}, bridge) == {:error, :unavailable}

      scan(Bridge.listen_port(bridge))
      await(fn -> registered(bridge).ip end, 1_000)

      assert Bridge.command(@key, {:zone, "rippleLightToggle", true}, bridge) ==
               {:error, :unavailable}

      assert Bridge.command(@key, {:scene, "Forest"}, bridge) == {:error, :unavailable}
      refute_receive {:api, "/router/api/v1/device/control", _body}, 100
    end

    test "a stored lamp the cloud has not listed is asked about neither by the poll nor for zones" do
      bridge = unlisted_bridge!([])
      port = Bridge.listen_port(bridge)

      scan(port)
      udp(port, status(%{"onOff" => 1, "brightness" => 30}))
      assert_receive {:state, @key, %{on: true, brightness: 30}}, 1_000

      send(bridge, :api_poll)
      :sys.get_state(bridge)
      settled(bridge)

      refute_receive {:api, "/router/api/v1/device/state", _body}, 100
    end
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
