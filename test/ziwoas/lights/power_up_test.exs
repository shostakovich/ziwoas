defmodule Ziwoas.Lights.PowerUpTest do
  use Ziwoas.DataCase

  import Ziwoas.LampPower

  alias Ziwoas.{Config, FakeGoveeBridge, FakeShelly, Lights, Repo, TestClock}
  alias Ziwoas.Lights.{Light, PowerUp}

  @start "2026-06-15T18:00:00Z"

  setup do
    TestClock.freeze(@start)
    start_supervised!({FakeGoveeBridge, test: self()})
    start_power_up!()
    Lights.subscribe("FL1")

    %{
      light: Repo.insert!(%Light{key: "FL1", name: "Stehlampe", shelly_plug_id: "fridge"}),
      plug: Enum.find(Config.get().plugs, &(&1.id == "fridge"))
    }
  end

  defp hear(telemetry), do: hear("FL1", telemetry)
  defp tick, do: tick("FL1")
  defp later(seconds), do: later(@start, seconds)

  defp sent do
    receive do
      {:govee, "FL1", verb} -> [verb | sent()]
    after
      0 -> []
    end
  end

  defp on, do: {"turn", %{on: true}}
  defp off, do: {"turn", %{on: false}}

  test "begin switches the plug on by hand, watches the lamp, and sends nothing yet",
       %{light: light, plug: plug} do
    FakeShelly.serve("fridge")
    assert PowerUp.begin(light, plug, on()) == :ok

    plug_switched_on("fridge")
    assert_received {:govee_watch, "FL1"}
    assert_received {:updated, "FL1"}

    assert PowerUp.starting() == %{
             "FL1" => %{since: ~U[2026-06-15 18:00:00.000000Z], on: true}
           }

    assert sent() == []
    assert plug_commands() == [{"fridge", :on, :manual}]
  end

  test "a plug that does not answer ends the attempt at once", %{light: light, plug: plug} do
    Lights.subscribe()
    assert PowerUp.begin(light, plug, on()) == :ok

    assert_receive {:power_up_failed, {"FL1", :plug_unreachable}}
    assert_receive {:govee_unwatch, "FL1"}
    assert PowerUp.starting() == %{}
  end

  test "a switching task that dies ends the attempt as an unreachable plug",
       %{light: light, plug: plug} do
    Lights.subscribe()
    FakeShelly.serve("fridge", fn _method, _params -> Process.sleep(:infinity) end)
    PowerUp.begin(light, plug, on())

    await(fn -> Task.Supervisor.children(Ziwoas.Lights.Tasks) != [] end)
    [task] = Task.Supervisor.children(Ziwoas.Lights.Tasks)
    Process.exit(task, :kill)

    assert_receive {:power_up_failed, {"FL1", :plug_unreachable}}
  end

  test "a plug failing after the lamp was heard ends nothing: the lamp has power",
       %{light: light, plug: plug} do
    Lights.subscribe()
    test = self()

    FakeShelly.serve("fridge", fn _method, _params ->
      send(test, {:switching, self()})

      receive do
        :answer -> {:error, {:rpc, -103, "busy"}}
      end
    end)

    PowerUp.begin(light, plug, on())
    assert_receive {:switching, shelly}
    hear(nil)
    assert sent() == [{:power, true}]

    send(shelly, :answer)
    await(fn -> Task.Supervisor.children(Ziwoas.Lights.Tasks) == [] end)
    :sys.get_state(PowerUp)

    refute_received {:power_up_failed, _failure}
    assert Map.has_key?(PowerUp.starting(), "FL1")
  end

  test "a second begin joins the attempt and switches no plug again",
       %{light: light, plug: plug} do
    FakeShelly.serve("fridge")
    PowerUp.begin(light, plug, on())
    plug_switched_on("fridge")

    assert PowerUp.begin(light, plug, {"brightness", %{value: 30}}) == :ok
    refute_receive {:shelly_rpc, _plug, _method, _params}, 50

    hear(nil)
    assert sent() == [{:power, true}, {:brightness, 30}]
  end

  test "an attempt begun by another command switches the lamp on as well",
       %{light: light, plug: plug} do
    FakeShelly.serve("fridge")
    PowerUp.begin(light, plug, {"brightness", %{value: 30}})
    plug_switched_on("fridge")

    hear(nil)
    assert sent() == [{:power, true}, {:brightness, 30}]
  end

  describe "once the plug is on" do
    setup %{light: light, plug: plug} do
      FakeShelly.serve("fridge")
      :ok = PowerUp.begin(light, plug, on())
      plug_switched_on("fridge")
    end

    test "the first reply sends the commands, a reply with the wanted power ends the attempt" do
      hear(nil)
      assert sent() == [{:power, true}]

      hear(%{on: true})
      assert_received {:govee_unwatch, "FL1"}
      assert PowerUp.starting() == %{}
    end

    test "an attempt that wants the lamp off ends once it reports off" do
      PowerUp.queue("FL1", off())
      assert %{"FL1" => %{on: false}} = PowerUp.starting()
      hear(nil)
      assert sent() == [{:power, false}]

      hear(%{on: true})
      refute_received {:govee_unwatch, "FL1"}

      hear(%{on: false})
      assert_received {:govee_unwatch, "FL1"}
    end

    test "a command after the first delivery goes out with the next reply" do
      hear(nil)
      assert sent() == [{:power, true}]

      assert PowerUp.queue("FL1", {"brightness", %{value: 60}}) == :queued
      hear(%{on: true})
      assert sent() == [{:power, true}, {:brightness, 60}]
      refute_received {:govee_unwatch, "FL1"}

      hear(%{on: true})
      assert_received {:govee_unwatch, "FL1"}
    end

    test "a lamp still showing the wrong power gets the commands again on the next tick" do
      hear(nil)
      assert sent() == [{:power, true}]

      hear(%{on: false})
      later(5)
      tick()
      assert sent() == [{:power, true}]
      assert Map.has_key?(PowerUp.starting(), "FL1")
    end

    test "a tick renews the watch, in case the bridge restarted, and sends nothing to a silent lamp" do
      assert_received {:govee_watch, "FL1"}
      later(30)
      tick()

      assert_received {:govee_watch, "FL1"}
      assert sent() == []
    end

    test "after 60 s a lamp that never answered gives up and says so" do
      Lights.subscribe()
      later(60)
      tick()

      assert_received {:power_up_failed, {"FL1", :timeout}}
      assert_received {:govee_unwatch, "FL1"}
      assert PowerUp.starting() == %{}

      hear(nil)
      assert sent() == []
    end

    test "after 60 s a lamp that answered sends what is pending and ends without a failure" do
      Lights.subscribe()
      hear(nil)
      assert sent() == [{:power, true}]
      PowerUp.queue("FL1", {"brightness", %{value: 60}})

      later(60)
      tick()

      assert sent() == [{:power, true}, {:brightness, 60}]
      assert_received {:govee_unwatch, "FL1"}
      refute_received {:power_up_failed, _failure}
      assert PowerUp.starting() == %{}
    end

    test "the last command per kind wins, colour and white are one kind, power goes first" do
      for command <- [
            {"brightness", %{value: 40}},
            {"color", %{r: 1, g: 2, b: 3}},
            {"brightness", %{value: 60}},
            on(),
            {"color_temp", %{temp_k: 2700}}
          ],
          do: assert(PowerUp.queue("FL1", command) == :queued)

      hear(nil)
      assert sent() == [{:power, true}, {:brightness, 60}, {:color_temp, 2700}]
    end

    test "each zone is a kind of its own" do
      zone = fn name, on -> {"zone", %{zone: name, on: on}} end

      PowerUp.queue("FL1", zone.("leftLightToggle", true))
      PowerUp.queue("FL1", zone.("rightLightToggle", true))
      PowerUp.queue("FL1", zone.("leftLightToggle", false))

      hear(nil)

      assert sent() == [
               {:power, true},
               {:zone, "rightLightToggle", true},
               {:zone, "leftLightToggle", false}
             ]
    end

    test "a command the lamp refused stays pending, is sent again, and fails the attempt at 60 s" do
      Lights.subscribe()
      stop_supervised!(FakeGoveeBridge)

      refuse_brightness = fn
        {:brightness, _value} -> {:error, :unknown_lamp}
        _verb -> :ok
      end

      start_supervised!({FakeGoveeBridge, test: self(), answer: refuse_brightness})
      later(5)
      tick()
      PowerUp.queue("FL1", {"brightness", %{value: 60}})

      hear(nil)
      assert sent() == [{:power, true}, {:brightness, 60}]

      hear(%{on: true})
      assert sent() == [{:power, true}, {:brightness, 60}]
      refute_received {:govee_unwatch, "FL1"}

      later(60)
      tick()
      assert_received {:power_up_failed, {"FL1", :timeout}}
    end

    test "off replaces everything; a command after it switches the lamp on again" do
      PowerUp.queue("FL1", {"brightness", %{value: 60}})
      PowerUp.queue("FL1", off())
      hear(nil)
      assert sent() == [{:power, false}]

      PowerUp.queue("FL1", {"brightness", %{value: 30}})
      assert %{"FL1" => %{on: true}} = PowerUp.starting()
      hear(%{on: false})
      assert sent() == [{:power, true}, {:brightness, 30}]
    end
  end

  test "an unexpected message changes nothing", %{light: light, plug: plug} do
    FakeShelly.serve("fridge")
    PowerUp.begin(light, plug, on())
    plug_switched_on("fridge")
    send(PowerUp, :stray)
    assert Map.has_key?(PowerUp.starting(), "FL1")
  end

  test "without an attempt queue is idle" do
    assert PowerUp.queue("FL1", on()) == :idle
  end

  test "without a bridge nothing can start", %{light: light, plug: plug} do
    stop_supervised!(FakeGoveeBridge)
    assert PowerUp.begin(light, plug, on()) == {:error, :unavailable}
    refute_received {:shelly_rpc, _plug, _method, _params}
    assert PowerUp.starting() == %{}
  end

  test "without a running power-up nothing is starting or queued", %{light: light, plug: plug} do
    stop_supervised!(PowerUp)
    assert PowerUp.starting() == %{}
    assert PowerUp.queue("FL1", on()) == :idle
    assert PowerUp.begin(light, plug, on()) == {:error, :unavailable}
  end
end
