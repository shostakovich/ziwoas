defmodule Ziwoas.Hue.BridgeTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Ziwoas.HueFixtures

  alias Ziwoas.Hue.Bridge
  alias Ziwoas.HueStub

  @moduletag :capture_log

  @hour :timer.hours(1)

  defp start_bridge!(opts \\ []) do
    test = self()

    defaults = [
      name: nil,
      put_lamp: &send(test, {:lamp, &1}),
      put_state: fn key, state ->
        send(test, {:state, key, state})
        {:ok, state}
      end,
      stored_keys: fn -> [] end
    ]

    HueStub.start_bridge!(Keyword.merge(defaults, opts))
  end

  test "loads every light as a lamp and stores its state" do
    start_bridge!()

    for name <- ["Twilight Back", "Twilight Front", "Kerzenlampe", "Farblicht"],
        do: assert_received({:lamp, %{name: ^name, vendor: :hue}})

    candle = key(candle())
    assert_received {:state, ^candle, %{on: true, brightness: 70, color_temp_k: 2703}}
    farblicht = key(colour_only())
    assert_received {:state, ^farblicht, %{on: false, reachable: false}}
  end

  test "opens the event stream before it reads the full state" do
    start_bridge!()

    paths =
      for _request <- 1..3 do
        assert_received {:hue, :get, path}
        path
      end

    assert paths == ["/api/0/config", "/eventstream/clip/v2", "/clip/v2/resource"]
  end

  test "a change in the Hue app reaches the lamp's state through the event stream" do
    dimmed =
      update([%{"id" => candle(), "type" => "light", "dimming" => %{"brightness" => 20.0}}])

    start_bridge!(events: fn 1 -> [dimmed] end)
    key = key(candle())

    assert_receive {:state, ^key, %{brightness: 70}}
    assert_receive {:state, ^key, %{on: true, brightness: 20, color_temp_k: 2703}}
  end

  test "an event stores the lamp's state even when the bridge reported it before" do
    {_bridge, stub} = start_bridge!()
    key = key(candle())
    assert_received {:state, ^key, %{on: true} = reported}

    HueStub.push(stub, [update([%{"id" => candle(), "type" => "light", "on" => %{"on" => true}}])])

    assert_received {:state, ^key, ^reported}
  end

  test "events it cannot read are skipped, the rest is taken" do
    {bridge, stub} = start_bridge!()
    key = key(candle())

    HueStub.push(stub, [
      %{"type" => "add", "data" => "x"},
      update(["x", %{"id" => candle(), "type" => "light", "dimming" => %{"brightness" => 20.0}}])
    ])

    assert Process.alive?(bridge)
    assert_received {:state, ^key, %{brightness: 20}}
  end

  test "a lamp the bridge loses touch with is stored unreachable" do
    lost =
      update([
        %{
          "id" => "00000009-0000-4000-8000-000000000009",
          "type" => "zigbee_connectivity",
          "status" => "connectivity_issue"
        }
      ])

    start_bridge!(events: fn 1 -> [lost] end)
    key = key(candle())

    assert_receive {:state, ^key, %{reachable: true}}
    assert_receive {:state, ^key, %{on: false, reachable: false}}
  end

  test "a light added on the bridge is read and stored as a lamp" do
    id = "000000ff-0000-4000-8000-0000000000ff"

    new =
      resource(candle())
      |> Map.drop(["owner"])
      |> Map.merge(%{"id" => id, "metadata" => %{"name" => "Neu"}})

    added = %{"type" => "add", "data" => [%{"id" => id, "type" => "light"}]}

    start_bridge!(
      events: fn 1 -> [added] end,
      resources: fn read -> if read == 1, do: resources(), else: [new | resources()] end
    )

    key = key(id)
    assert_receive {:lamp, %{key: ^key, name: "Neu"}}
  end

  test "a light deleted on the bridge reads the full state again" do
    deleted = %{"type" => "delete", "data" => [%{"id" => candle(), "type" => "light"}]}
    {bridge, _stub} = start_bridge!(events: fn 1 -> [deleted] end)
    assert_received {:hue, :get, "/clip/v2/resource"}

    :sys.get_state(bridge)
    assert_received {:hue, :get, "/clip/v2/resource"}
  end

  test "a stored lamp the bridge no longer has is stored off and unreachable" do
    start_bridge!(stored_keys: fn -> ["GONE", key(candle())] end)

    assert_received {:state, "GONE", %{on: false, reachable: false}}
    candle = key(candle())
    assert_received {:state, ^candle, %{on: true}}
    refute_received {:state, ^candle, %{on: false}}
  end

  test "an added resource ZiWoAS does not keep reads nothing" do
    added = %{"type" => "add", "data" => [%{"id" => "b", "type" => "button"}]}
    {bridge, _stub} = start_bridge!(events: fn 1 -> [added] end)
    assert_received {:hue, :get, "/clip/v2/resource"}

    :sys.get_state(bridge)
    refute_received {:hue, :get, "/clip/v2/resource"}
  end

  test "after the event stream drops, the reconnect reconciles the full state" do
    off = resources_with(candle(), %{"on" => %{"on" => false}})

    {_bridge, stub} =
      start_bridge!(
        retry_ms: 10,
        resources: fn read -> if read == 1, do: resources(), else: off end
      )

    key = key(candle())
    assert_received {:state, ^key, %{on: true}}

    HueStub.drop(stub)

    assert_receive {:hue, :get, "/eventstream/clip/v2"}
    assert_receive {:hue, :get, "/eventstream/clip/v2"}
    assert_receive {:state, ^key, %{on: false}}
  end

  test "a reconnect keeps the bridge ID it learned instead of asking again" do
    {bridge, stub} = start_bridge!(retry_ms: 10)
    assert_received {:hue, :get, "/api/0/config"}
    assert_received {:hue, :get, "/eventstream/clip/v2"}

    HueStub.drop(stub)
    assert_receive {:hue, :get, "/eventstream/clip/v2"}
    :sys.get_state(bridge)

    refute_received {:hue, :get, "/api/0/config"}
    assert :sys.get_state(bridge).client.bridge_id == "001788fffe6a1b2c"
  end

  test "an event stream silent for too long is dropped and reopened, without a warning" do
    log =
      capture_log([level: :warning], fn ->
        start_bridge!(retry_ms: 1, idle_ms: 20)

        assert_received {:hue, :get, "/eventstream/clip/v2"}
        assert_receive :hue_stream_cancelled
        assert_receive {:hue, :get, "/eventstream/clip/v2"}
      end)

    refute log =~ "event stream ended"
  end

  test "an event stream the bridge ends is a warning" do
    {_bridge, stub} = start_bridge!()
    log = capture_log([level: :warning], fn -> HueStub.drop(stub) end)
    assert log =~ "event stream ended: :closed"
  end

  test "an event stream that sends more than 1 MB without ending an event is dropped" do
    {_bridge, stub} = start_bridge!()

    HueStub.push_raw(stub, "data: " <> String.duplicate("x", 1_048_570))
    refute_received :hue_stream_cancelled

    HueStub.push_raw(stub, "x")
    assert_received :hue_stream_cancelled
  end

  test "a bridge it cannot reach is retried" do
    start_bridge!(config: {503, ""}, retry_ms: 10)

    assert_received {:hue, :get, "/api/0/config"}
    assert_receive {:hue, :get, "/api/0/config"}
  end

  describe "the backoff" do
    test "doubles with every failed connect, up to its cap" do
      {bridge, _stub} =
        start_bridge!(config: {503, ""}, retry_ms: @hour, retry_max_ms: 3 * @hour)

      assert :sys.get_state(bridge).retry_ms == 2 * @hour

      send(bridge, :connect)
      assert :sys.get_state(bridge).retry_ms == 3 * @hour

      send(bridge, :connect)
      assert :sys.get_state(bridge).retry_ms == 3 * @hour
    end

    test "starts over once a stream has held for the stable time, and only then" do
      for {stable_ms, retry_ms} <- [{0, 2 * @hour}, {@hour, 4 * @hour}] do
        {bridge, stub} =
          start_bridge!(
            resources: fn read -> if read == 1, do: {503, ""}, else: resources() end,
            retry_ms: @hour,
            retry_max_ms: 10 * @hour,
            stable_ms: stable_ms
          )

        assert :sys.get_state(bridge).retry_ms == 2 * @hour
        send(bridge, :connect)
        assert :sys.get_state(bridge).stream
        HueStub.drop(stub)

        assert :sys.get_state(bridge).retry_ms == retry_ms
        stop_supervised!(Bridge)
        stop_supervised!(HueStub)
      end
    end
  end

  test "a full read that fails closes the event stream it opened" do
    start_bridge!(resources: fn _read -> {503, ""} end)

    assert_received {:hue, :get, "/eventstream/clip/v2"}
    assert_received :hue_stream_cancelled
  end

  test "a reload that fails keeps the lamps the bridge knows" do
    added = %{"type" => "add", "data" => [%{"id" => "new", "type" => "light"}]}

    {{bridge, _stub}, log} =
      with_log([level: :warning], fn ->
        {bridge, stub} =
          start_bridge!(
            events: fn 1 -> [added] end,
            resources: fn read -> if read == 1, do: resources(), else: {503, ""} end
          )

        assert_receive {:hue, :get, "/clip/v2/resource"}
        assert_receive {:hue, :get, "/clip/v2/resource"}
        :sys.get_state(bridge)
        {bridge, stub}
      end)

    assert log =~ "reload failed"
    assert Bridge.command(key(candle()), {:power, false}, bridge) == :ok
  end

  test "a lamp the store refuses leaves the other lamps and the states" do
    log =
      capture_log([level: :warning], fn ->
        start_bridge!(
          put_lamp: fn lamp -> if lamp.name == "Kerzenlampe", do: {:error, :invalid} end
        )
      end)

    assert log =~ "lamp #{key(candle())} refused: :invalid"
    assert_received {:state, _key, _state}
  end

  describe "a command" do
    test "becomes the light's update, sent with the key" do
      {bridge, _stub} = start_bridge!()
      id = candle()

      assert Bridge.command(key(id), {:brightness, 40}, bridge) == :ok

      assert_received {:hue_put, ^id,
                       %{"on" => %{"on" => true}, "dimming" => %{"brightness" => 40}}}
    end

    test "for each light source of a device reaches only that light" do
      {bridge, _stub} = start_bridge!()

      assert Bridge.command(key(twilight_back()), {:power, false}, bridge) == :ok
      back = twilight_back()
      assert_received {:hue_put, ^back, _body}
      refute_received {:hue_put, _id, _body}
    end

    test "that the lamp cannot do, or for a lamp the bridge does not know, sends nothing" do
      {bridge, _stub} = start_bridge!()

      assert Bridge.command(key(candle()), {:color, %{r: 1, g: 2, b: 3}}, bridge) ==
               {:error, :unsupported}

      assert Bridge.command("0000", {:power, true}, bridge) == {:error, :unknown_lamp}
      refute_received {:hue_put, _id, _body}
    end

    test "the bridge refuses is an error" do
      {bridge, _stub} =
        start_bridge!(put: fn _id -> {400, ~s({"errors":[{"description":"invalid"}]})} end)

      assert Bridge.command(key(candle()), {:power, true}, bridge) ==
               {:error, {:hue, ["invalid"]}}
    end

    test "without a running bridge is unavailable" do
      assert Bridge.command("abc", {:power, true}, nil) == {:error, :unavailable}
    end
  end

  describe "a lamp" do
    test "is silent while the bridge reports its Zigbee connection not connected" do
      {bridge, _stub} = start_bridge!()

      assert Bridge.silent?(key(colour_only()), bridge)
      refute Bridge.silent?(key(candle()), bridge)
    end

    test "falls silent when the bridge loses touch with it" do
      {bridge, stub} = start_bridge!()

      HueStub.push(stub, [connectivity(candle_connectivity(), "connectivity_issue")])

      assert Bridge.silent?(key(candle()), bridge)
    end

    test "the bridge does not know, or without a running bridge, is not silent" do
      {bridge, _stub} = start_bridge!()

      refute Bridge.silent?("0000", bridge)
      refute Bridge.silent?(key(colour_only()), nil)
    end
  end

  describe "a watched lamp" do
    test "is heard, with its state, on an event the bridge sends for it" do
      {bridge, stub} = start_bridge!()
      key = key(candle())
      assert Bridge.watch(key, bridge, self()) == :ok

      HueStub.push(stub, [
        update([%{"id" => candle(), "type" => "light", "dimming" => %{"brightness" => 20.0}}])
      ])

      assert_received {:lamp_heard, ^key, %{on: true, reachable: true, brightness: 20}}
    end

    test "is not heard on an event that reports it not connected, but on the one that it is" do
      {bridge, stub} = start_bridge!()
      key = key(candle())
      Bridge.watch(key, bridge, self())

      HueStub.push(stub, [connectivity(candle_connectivity(), "connectivity_issue")])
      refute_received {:lamp_heard, ^key, _state}

      HueStub.push(stub, [connectivity(candle_connectivity(), "connected")])
      assert_received {:lamp_heard, ^key, %{reachable: true}}
    end

    test "with two light sources is heard as both through their device's Zigbee connection" do
      {bridge, stub} = start_bridge!()
      [back, front] = [key(twilight_back()), key(twilight_front())]
      Bridge.watch(back, bridge, self())
      Bridge.watch(front, bridge, self())

      HueStub.push(stub, [connectivity(twilight_connectivity(), "connected")])

      assert_received {:lamp_heard, ^back, _state}
      assert_received {:lamp_heard, ^front, _state}
    end

    test "is not heard on events for other lamps, nor once unwatched" do
      {bridge, stub} = start_bridge!()
      key = key(candle())
      Bridge.watch(key, bridge, self())

      HueStub.push(stub, [connectivity(twilight_connectivity(), "connected")])
      assert Bridge.unwatch(key, bridge) == :ok
      HueStub.push(stub, [connectivity(candle_connectivity(), "connected")])

      refute_received {:lamp_heard, _key, _state}
    end

    test "stays watched across a dropped stream, whose full read does not count as hearing it" do
      {bridge, stub} = start_bridge!(retry_ms: 1)
      key = key(candle())
      Bridge.watch(key, bridge, self())

      HueStub.drop(stub)
      assert_receive {:hue, :get, "/clip/v2/resource"}
      assert_receive {:hue, :get, "/clip/v2/resource"}
      :sys.get_state(bridge)
      refute_received {:lamp_heard, ^key, _state}

      HueStub.push(stub, [connectivity(candle_connectivity(), "connected")])
      assert_received {:lamp_heard, ^key, _state}
    end

    test "is forgotten when its watcher exits" do
      {bridge, _stub} = start_bridge!()
      watcher = spawn(fn -> :ok end)
      ref = Process.monitor(watcher)
      assert_receive {:DOWN, ^ref, :process, _pid, _reason}

      Bridge.watch(key(candle()), bridge, watcher)

      assert :sys.get_state(bridge).watchers == %{}
    end

    test "cannot be watched without a running bridge" do
      assert Bridge.watch("abc", nil) == {:error, :unavailable}
      assert Bridge.unwatch("abc", nil) == :ok
    end
  end
end
