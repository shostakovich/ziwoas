defmodule Ziwoas.Shelly.ListenerTest do
  use Ziwoas.DataCase

  alias Ziwoas.{FakeShellyDevice, Repo, Shelly, TestConfigs}
  alias Ziwoas.Plugs.Sample

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
    {:ok, {_ip, port}} = ThousandIsland.listener_info(listener)
    %{port: port}
  end

  defp await(fun, timeout \\ 1_000) do
    cond do
      fun.() -> :ok
      timeout <= 0 -> flunk("condition not met")
      true -> Process.sleep(10) && await(fun, timeout - 10)
    end
  end

  test "a Shelly reports its status and takes calls", %{port: port} do
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

    await(fn -> Repo.exists?(Sample) end)
    assert [%Sample{plug_id: "fridge", apower_w: 42.0, aenergy_wh: 7.0}] = Repo.all(Sample)

    assert Shelly.call("fridge", "Switch.Set", %{id: 0, on: false}) == {:ok, %{"was_on" => false}}
    assert_received {:shelly_request, "fridge", "Switch.Set", %{"id" => 0, "on" => false}}
  end

  test "a path that names no Shelly plug is not found", %{port: port} do
    for path <- ["/shelly/toaster", "/shelly/washer", "/shelly", "/shelly/fridge/x", "/"] do
      assert FakeShellyDevice.handshake(port, path) == {:error, 404}, path
    end
  end
end
