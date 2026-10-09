defmodule Ziwoas.Lights.CommandsTest do
  use Ziwoas.DataCase

  import Ziwoas.LampPower

  alias Ziwoas.{FakeGoveeBridge, FakeShelly, Plugs, Repo, TestClock, TestConfigs}
  alias Ziwoas.Lights.{Commands, Light, PowerUp, State}

  setup do
    TestClock.freeze("2026-06-15T18:00:00Z")
    :ok
  end

  defp bridge!(answer \\ :ok),
    do: start_supervised!({FakeGoveeBridge, test: self(), answer: answer})

  defp light!(attrs), do: Repo.insert!(struct!(%Light{name: "L"}, attrs))
  defp state(key), do: Repo.get_by(State, light_key: key)

  defp sent do
    receive do
      {:govee, key, verb} -> [{key, verb} | sent()]
    after
      0 -> []
    end
  end

  describe "turn" do
    setup do: %{bridge: bridge!()}

    test "a simple lamp gets the power verb; the state is recorded; the hero redraws" do
      light!(%{key: "S1", zones: []})
      assert {:ok, :power} = Commands.run(light!(%{key: "S0"}), "turn", %{"on" => "true"})
      assert {:ok, :power} = Commands.run(Repo.get_by(Light, key: "S1"), "turn", %{"on" => false})

      assert sent() == [{"S0", {:power, true}}, {"S1", {:power, false}}]

      assert %State{on: true, zone_states: nil} = state("S0")
      assert %State{on: false} = state("S1")
    end

    test "a zone lamp routes power through powerSwitch" do
      light = light!(%{key: "U1", zones: ~w[bottomLightToggle sideLightToggle]})
      Commands.run(light, "turn", %{"on" => "1"})
      assert sent() == [{"U1", {:zone, "powerSwitch", true}}]
    end

    test "an unchanged state is not written again" do
      light = light!(%{key: "S2"})
      Repo.insert!(%State{light_key: "S2", on: true, updated_at: ~U[2026-01-01 00:00:00.000000Z]})
      Commands.run(light, "turn", %{"on" => "true"})
      assert state("S2").updated_at == ~U[2026-01-01 00:00:00.000000Z]
    end

    test "a flag that does not cast is invalid and sends nothing" do
      light = light!(%{key: "S3"})

      for params <- [%{"on" => ""}, %{"on" => "maybe"}, %{}] do
        assert {:error, :invalid} = Commands.run(light, "turn", params)
      end

      assert sent() == []
    end

    test "a refused verb is unreachable and records nothing", %{bridge: bridge} do
      stop_supervised!(FakeGoveeBridge)
      refute Process.alive?(bridge)
      bridge!({:error, :unknown_lamp})
      light = light!(%{key: "S4"})
      assert {:error, :unreachable} = Commands.run(light, "turn", %{"on" => "true"})
      assert state("S4") == nil
    end

    test "without a running bridge the lamp is unreachable" do
      stop_supervised!(FakeGoveeBridge)
      light = light!(%{key: "S5"})
      assert {:error, :unreachable} = Commands.run(light, "turn", %{"on" => "true"})
      assert state("S5") == nil
    end
  end

  describe "values" do
    setup do
      bridge!()
      %{light: light!(%{key: "C1", color_temp_min_k: 2700, color_temp_max_k: 6500})}
    end

    test "brightness, colour, white and scenes are fire and forget", %{light: light} do
      assert {:ok, {:sent, {:brightness, 42}}} =
               Commands.run(light, "brightness", %{"value" => "42"})

      assert {:ok, {:sent, {:color, %{r: 10, g: 20, b: 30}}}} =
               Commands.run(light, "color", %{"r" => "10", "g" => "20", "b" => 30})

      assert {:ok, {:sent, {:color_temp, 2700}}} =
               Commands.run(light, "color_temp", %{"temp_k" => "2200"})

      assert {:ok, {:sent, {:color_temp, 6500}}} =
               Commands.run(light, "color_temp", %{"temp_k" => "9000"})

      assert {:ok, {:sent, {:scene, "Forest"}}} =
               Commands.run(light, "effect", %{"effect" => "Forest"})

      assert {:ok, {:sent, {:scene, "Rock & <Roll>"}}} =
               Commands.run(light, "scene", %{"scene" => "Rock & <Roll>"})

      assert sent() == [
               {"C1", {:brightness, 42}},
               {"C1", {:color, %{r: 10, g: 20, b: 30}}},
               {"C1", {:color_temp, 2700}},
               {"C1", {:color_temp, 6500}},
               {"C1", {:scene, "Forest"}},
               {"C1", {:scene, "Rock & <Roll>"}}
             ]

      assert state("C1") == nil
    end

    test "out of range or uncoercible values are invalid", %{light: light} do
      for {command, params} <- [
            {"brightness", %{"value" => "0"}},
            {"brightness", %{"value" => "101"}},
            {"brightness", %{"value" => "4.5"}},
            {"color", %{"r" => "256", "g" => "0", "b" => "0"}},
            {"color", %{"r" => "1", "g" => "2"}},
            {"color_temp", %{"temp_k" => "1499"}},
            {"color_temp", %{"temp_k" => "9001"}},
            {"effect", %{"effect" => ""}},
            {"scene", %{}},
            {"explode", %{}}
          ] do
        assert {:error, :invalid} = Commands.run(light, command, params),
               "#{command} #{inspect(params)}"
      end

      assert sent() == []
    end
  end

  describe "zones" do
    setup do: %{bridge: bridge!()}

    test "a valid zone is switched and recorded, without a toast" do
      light = light!(%{key: "Z0", zones: ~w[bottomLightToggle rippleLightToggle]})

      assert {:ok, {:zones, ["rippleLightToggle"], nil}} =
               Commands.run(light, "zone", %{"zone" => "rippleLightToggle", "on" => "true"})

      assert sent() == [{"Z0", {:zone, "rippleLightToggle", true}}]
      assert state("Z0").zone_states == %{"rippleLightToggle" => true}
    end

    test "a zone the lamp does not have is invalid" do
      light = light!(%{key: "Z2", zones: ~w[bottomLightToggle]})

      assert {:error, :invalid} =
               Commands.run(light, "zone", %{"zone" => "powerSwitch", "on" => "true"})

      assert {:error, :invalid} = Commands.run(light, "zone", %{"zone" => "bottomLightToggle"})
    end

    test "over the limit, a lit side zone is evicted and a toast offers the undo" do
      light =
        light!(%{
          key: "Z1",
          sku: "H60B0",
          zones: ~w[bottomLightToggle rippleLightToggle sideLightToggle]
        })

      Commands.record_zone_state("Z1", "bottomLightToggle", true)
      Commands.record_zone_state("Z1", "rippleLightToggle", true)

      assert {:ok, {:zones, ["sideLightToggle", "rippleLightToggle"], toast}} =
               Commands.run(light, "zone", %{"zone" => "sideLightToggle", "on" => "true"})

      assert toast == %{evicted: "rippleLightToggle", added: "sideLightToggle"}

      assert sent() == [
               {"Z1", {:zone, "rippleLightToggle", false}},
               {"Z1", {:zone, "sideLightToggle", true}}
             ]

      assert state("Z1").zone_states ==
               %{
                 "bottomLightToggle" => true,
                 "rippleLightToggle" => false,
                 "sideLightToggle" => true
               }
    end

    test "a zone bit merges into the stored zones, creating the row when missing" do
      Commands.record_zone_state("Z4", "mainLightToggle", true)
      Commands.record_zone_state("Z4", "backgroundLightToggle", false)
      Commands.record_zone_state("Z4", "mainLightToggle", false)

      assert state("Z4").zone_states == %{
               "mainLightToggle" => false,
               "backgroundLightToggle" => false
             }
    end

    test "an unchanged zone bit is not written again" do
      Commands.record_zone_state("Z5", "mainLightToggle", true)
      stamp = state("Z5").updated_at
      TestClock.freeze("2026-06-15T19:00:00Z")
      Commands.record_zone_state("Z5", "mainLightToggle", true)
      assert state("Z5").updated_at == stamp
    end

    test "an unreachable lamp leaves the stored zones alone" do
      stop_supervised!(FakeGoveeBridge)
      light = light!(%{key: "K", sku: "H60B0", zones: ~w[rippleLightToggle sideLightToggle]})
      Repo.insert!(%State{light_key: "K", zone_states: %{}})

      assert {:error, :unreachable} =
               Commands.run(light, "zone", %{"zone" => "rippleLightToggle", "on" => "true"})

      assert state("K").zone_states == %{}
    end

    test "undo restores the victim, switches the added zone off and clears the toast" do
      light = light!(%{key: "Z3", zones: ~w[rippleLightToggle sideLightToggle]})
      Commands.record_zone_state("Z3", "sideLightToggle", true)

      assert {:ok, {:zones, ["rippleLightToggle", "sideLightToggle"], :clear}} =
               Commands.run(light, "zone_undo", %{
                 "victim" => "rippleLightToggle",
                 "added" => "sideLightToggle"
               })

      assert state("Z3").zone_states == %{"rippleLightToggle" => true, "sideLightToggle" => false}

      assert {:error, :invalid} =
               Commands.run(light, "zone_undo", %{
                 "victim" => "nope",
                 "added" => "sideLightToggle"
               })
    end
  end

  describe "a lamp on a plug" do
    setup do
      start_power_up!()
      %{light: light!(%{key: "FL1", shelly_plug_id: "fridge"})}
    end

    defp relay!(output), do: Repo.insert!(%Plugs.State{plug_id: "fridge", output: output})

    test "an unpowered lamp switches its plug on and starts", %{light: light} do
      bridge!()
      FakeShelly.serve("fridge")
      relay!(false)

      assert {:ok, :starting} = Commands.run(light, "turn", %{"on" => "true"})

      plug_switched_on("fridge")
      assert_received {:govee_watch, "FL1"}
      assert sent() == []
      assert Map.has_key?(PowerUp.starting(), "FL1")
    end

    test "an unpowered lamp switched off is recorded off and switches no plug", %{light: light} do
      bridge!()
      FakeShelly.serve("fridge")
      relay!(false)
      Repo.insert!(%State{light_key: "FL1", on: true})

      assert {:ok, :power} = Commands.run(light, "turn", %{"on" => "false"})

      refute_received {:shelly_rpc, _plug, _method, _params}
      assert sent() == []
      refute state("FL1").on
    end

    test "a silent lamp on a live plug starts as well", %{light: light} do
      start_supervised!({FakeGoveeBridge, test: self(), silent: ["FL1"]})
      FakeShelly.serve("fridge")
      relay!(true)

      assert {:ok, :starting} = Commands.run(light, "brightness", %{"value" => "40"})
      plug_switched_on("fridge")
    end

    test "a silent lamp switched off gets the off at once", %{light: light} do
      start_supervised!({FakeGoveeBridge, test: self(), silent: ["FL1"]})
      relay!(true)

      assert {:ok, :power} = Commands.run(light, "turn", %{"on" => "false"})
      assert sent() == [{"FL1", {:power, false}}]
    end

    test "a heard lamp on a live plug, or one whose relay is unknown, is switched at once",
         %{light: light} do
      bridge!()
      FakeShelly.serve("fridge")
      assert {:ok, :power} = Commands.run(light, "turn", %{"on" => "true"})

      relay!(true)
      assert {:ok, :power} = Commands.run(light, "turn", %{"on" => "true"})

      assert sent() == [{"FL1", {:power, true}}, {"FL1", {:power, true}}]
      refute_received {:shelly_rpc, _plug, _method, _params}
    end

    test "a plug that is not switchable powers no lamp", %{light: light} do
      TestConfigs.put(TestConfigs.plugs())
      bridge!()
      FakeShelly.serve("fridge")
      relay!(false)

      assert {:ok, :power} = Commands.run(light, "turn", %{"on" => "true"})
      assert sent() == [{"FL1", {:power, true}}]
      refute_received {:shelly_rpc, _plug, _method, _params}
    end

    test "an unreachable plug ends the attempt with a failure", %{light: light} do
      Ziwoas.Lights.subscribe()
      bridge!()
      relay!(false)

      assert {:ok, :starting} = Commands.run(light, "turn", %{"on" => "true"})
      assert_receive {:power_up_failed, {"FL1", :plug_unreachable}}
      assert PowerUp.starting() == %{}
    end

    test "without a bridge an unpowered lamp is unreachable", %{light: light} do
      relay!(false)
      assert {:error, :unreachable} = Commands.run(light, "turn", %{"on" => "true"})
    end

    test "a command during an attempt joins it and is not sent", %{light: light} do
      bridge!()
      FakeShelly.serve("fridge")
      relay!(false)
      assert {:ok, :starting} = Commands.run(light, "turn", %{"on" => "true"})
      plug_switched_on("fridge")

      assert {:ok, :starting} = Commands.run(light, "brightness", %{"value" => "40"})
      assert {:ok, :starting} = Commands.run(light, "turn", %{"on" => "false"})
      assert sent() == []
    end

    test "a command that does not cast is refused before any plug moves", %{light: light} do
      bridge!()
      FakeShelly.serve("fridge")
      relay!(false)
      assert {:error, :invalid} = Commands.run(light, "brightness", %{"value" => "0"})
      refute_received {:shelly_rpc, _plug, _method, _params}
    end
  end

  test "the known command names" do
    for name <- ~w[turn zone brightness color color_temp effect scene zone_undo],
        do: assert(Commands.command?(name))

    refute Commands.command?("explode")
    refute Commands.command?(["turn"])
  end
end
