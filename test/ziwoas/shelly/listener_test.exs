defmodule Ziwoas.Shelly.ListenerTest do
  use Ziwoas.DataCase

  import ExUnit.CaptureLog

  alias Ziwoas.{FakeShellyDevice, Plugs, Repo, Shelly, TestConfigs}
  alias Ziwoas.Plugs.Sample
  alias Ziwoas.Shelly.Server

  @moduletag :capture_log
  @moduletag :shared_sandbox

  @washer """
    - id: washer
      name: Waschmaschine
      role: consumer
      driver: fritz_dect
      ain: "08761 0500475"
  fritz_box:
    host: fritz.box
    user: u
    password: p
  fritz_poll:
    active_interval_seconds: 5
    idle_interval_seconds: 60
    idle_threshold_w: 10
    timeout_seconds: 2
  """

  setup do
    config = TestConfigs.plugs(@washer)
    listener = start_supervised!(Shelly.listener_spec(config, 0))
    port = Server.port(listener)
    %{port: port, config: config}
  end

  test "a Shelly reports its status and takes calls", %{port: port} do
    Plugs.subscribe()
    device = start_supervised!({FakeShellyDevice, port: port, plug_id: "fridge", test: self()})
    assert_receive {:shelly_request, "fridge", "Shelly.GetStatus", %{}}

    FakeShellyDevice.notify(device, %{
      "src" => "shellyplugsg3-test",
      "dst" => "ws",
      "method" => "NotifyFullStatus",
      "params" => %{
        "ts" => 1_700_000_000.0,
        "switch:0" => %{"output" => true, "apower" => 42.0, "aenergy" => %{"total" => 7.0}}
      }
    })

    assert_receive {:live, [%{id: "fridge"}]}
    assert [%Sample{plug_id: "fridge", apower_w: 42.0, aenergy_wh: 7.0}] = Repo.all(Sample)

    assert Shelly.call("fridge", "Switch.Set", %{id: 0, on: false}) == {:ok, %{"was_on" => false}}
    assert_received {:shelly_request, "fridge", "Switch.Set", %{"id" => 0, "on" => false}}
  end

  test "a path that names no Shelly plug is not found", %{port: port} do
    for path <- ["/shelly/toaster", "/shelly/washer", "/shelly", "/shelly/fridge/x", "/"] do
      assert FakeShellyDevice.handshake(port, path) == {:error, 404}, path
    end
  end

  test "a request for a Shelly plug without a websocket upgrade is a bad request", %{port: port} do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    :ok = :gen_tcp.send(socket, "GET /shelly/fridge HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")

    assert {:ok, "HTTP/1.1 400 " <> _rest} = :gen_tcp.recv(socket, 0, 1_000)
  end

  test "a port in use is retried without stopping anything, until it is free", %{config: config} do
    {:ok, busy} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(busy)
    spec = Supervisor.child_spec(Shelly.listener_spec(config, port), id: :busy)

    {listener, log} = with_log(fn -> start_supervised!(spec) end)
    assert log =~ "Shelly listener on port #{port}: :eaddrinuse; retrying in 1000 ms"

    :gen_tcp.close(busy)
    send(listener, :listen)
    :sys.get_state(listener)

    assert FakeShellyDevice.handshake(port, "/shelly/toaster") == {:error, 404}
  end
end
