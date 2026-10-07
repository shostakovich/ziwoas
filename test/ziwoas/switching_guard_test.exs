defmodule Ziwoas.SwitchingGuardTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Clock, Config, FakeShellyDevice, Shelly, Switching, TestClock}
  alias Ziwoas.Plugs.Plug
  alias Ziwoas.Switching.ScheduleTickJob

  @moduletag :capture_log
  @moduletag :shared_sandbox
  @fridge %Plug{id: "fridge", role: :consumer, driver: :shelly, switchable: true}

  setup do
    config = Config.get()
    listener = start_supervised!(Shelly.listener_spec(config, 0))
    {:ok, {_ip, port}} = ThousandIsland.listener_info(listener)

    start_supervised!({FakeShellyDevice, port: port, plug_id: "fridge", test: self()})
    assert_receive {:shelly_request, "fridge", "Shelly.GetStatus", _params}

    TestClock.freeze("2026-06-15T18:05:00+02:00")
    Switching.save_window("fridge", %{on_at_time: "18:00", off_at_time: "23:00", days: [1]})

    %{config: config}
  end

  test "the commands reach the plug", ctx do
    assert [{"fridge", _edge, :ok}] = ScheduleTickJob.tick(ctx.config, Clock.now())
    assert {:ok, _command} = Switching.switch(@fridge, :off, :manual)

    assert_received {:shelly_request, "fridge", "Switch.Set", %{"id" => 0, "on" => true}}
    assert_received {:shelly_request, "fridge", "Switch.Set", %{"id" => 0, "on" => false}}
  end
end
