defmodule Ziwoas.Govee.MessagesTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Govee.{Device, Messages}

  describe "state/1" do
    test "defaults to off and reachable; only the given readings are kept" do
      assert Messages.state(%{}) == {:ok, %{on: false, reachable: true}}

      assert Messages.state(%{"on" => true, "brightness" => "55", "brightness_x" => 1}) ==
               {:ok, %{on: true, reachable: true, brightness: 55}}
    end

    test "nil values are dropped, so the defaults apply" do
      assert Messages.state(%{"on" => nil, "reachable" => nil, "brightness" => nil}) ==
               {:ok, %{on: false, reachable: true}}
    end

    test "colour, colour temperature and zones coerce" do
      assert {:ok, state} =
               Messages.state(%{
                 "on" => "1",
                 "reachable" => "false",
                 "color" => %{"r" => "255", "g" => 128, "b" => 0},
                 "color_temp_k" => "2700",
                 "zone_states" => %{"rippleLightToggle" => "on", "sideLightToggle" => 0}
               })

      assert state == %{
               on: true,
               reachable: false,
               color: %{r: 255, g: 128, b: 0},
               color_temp_k: 2700,
               zone_states: %{"rippleLightToggle" => true, "sideLightToggle" => false}
             }
    end

    test "atom keys work as well, for the bridge's own store maps" do
      assert Messages.state(%{on: true, color: %{r: 1, g: 2, b: 3}}) ==
               {:ok, %{on: true, reachable: true, color: %{r: 1, g: 2, b: 3}}}
    end

    test "broken messages do not coerce" do
      for bad <- [
            %{"on" => "perhaps"},
            %{"brightness" => 101},
            %{"brightness" => "bright"},
            %{"color" => %{"r" => 1, "g" => 2}},
            %{"color" => %{"r" => 1, "g" => 2, "b" => 300}},
            %{"color" => "#ff0000"},
            %{"color_temp_k" => -1},
            %{"zone_states" => %{"" => true}},
            %{"zone_states" => %{"rippleLightToggle" => "x"}},
            %{"zone_states" => ["rippleLightToggle"]}
          ],
          do: assert(Messages.state(bad) == :error, inspect(bad))

      assert Messages.state(nil) == :error
      assert Messages.state("{}") == :error
      assert Messages.state([{"on", true}]) == :error
    end

    test "the wire object holds what the state has and reads back the same" do
      state = %{
        on: true,
        reachable: true,
        brightness: 40,
        color: %{r: 1, g: 2, b: 3},
        zone_states: %{"sideLightToggle" => true}
      }

      wire = Messages.state_wire(state)

      assert wire == %{
               "on" => true,
               "reachable" => true,
               "brightness" => 40,
               "color" => %{"r" => 1, "g" => 2, "b" => 3},
               "zone_states" => %{"sideLightToggle" => true}
             }

      assert wire |> JSON.encode!() |> JSON.decode!() |> Messages.state() == {:ok, state}

      assert Messages.state_wire(%{on: false, reachable: false}) == %{
               "on" => false,
               "reachable" => false
             }
    end
  end

  describe "config/1" do
    test "defaults for a bare config" do
      assert Messages.config(%{}) ==
               {:ok,
                %{
                  sku: "",
                  name: "",
                  supports_color: false,
                  supports_color_temp: false,
                  color_temp_min_k: nil,
                  color_temp_max_k: nil,
                  zones: [],
                  scenes: []
                }}
    end

    test "a full config" do
      assert {:ok, config} =
               Messages.config(%{
                 "sku" => "H60B0",
                 "name" => "Uplighter",
                 "supports_color" => "true",
                 "supports_color_temp" => 1,
                 "color_temp_min_k" => 2700,
                 "color_temp_max_k" => 6500,
                 "zones" => ["rippleLightToggle"],
                 "scenes" => ["Forest", "Aurora"]
               })

      assert config.supports_color and config.supports_color_temp

      assert {config.color_temp_min_k, config.zones, config.scenes} ==
               {2700, ["rippleLightToggle"], ["Forest", "Aurora"]}
    end

    test "strict where the bridge writes the values itself" do
      for bad <- [
            %{"sku" => 60},
            %{"name" => nil, "sku" => ["H60B0"]},
            %{"color_temp_min_k" => "2700"},
            %{"zones" => "rippleLightToggle"},
            %{"zones" => ["rippleLightToggle", ""]},
            %{"scenes" => [1]}
          ],
          do: assert(Messages.config(bad) == :error, inspect(bad))

      assert Messages.config(nil) == :error
    end

    test "a device's wire object reads back as its config" do
      device = %Device{
        key: "K",
        api_id: "AA:BB",
        sku: "H6008",
        name: "Bulb",
        supports_color: true,
        color_temp_min_k: 2000,
        color_temp_max_k: 9000,
        scenes: ["Forest"]
      }

      assert {:ok, config} =
               device
               |> Messages.config_wire()
               |> JSON.encode!()
               |> JSON.decode!()
               |> Messages.config()

      assert config == %{
               sku: "H6008",
               name: "Bulb",
               supports_color: true,
               supports_color_temp: false,
               color_temp_min_k: 2000,
               color_temp_max_k: 9000,
               zones: [],
               scenes: ["Forest"]
             }
    end
  end

  describe "device_telemetry/2" do
    test "power, brightness and the zones the lamp has" do
      map = %{
        "online" => true,
        "powerSwitch" => 1,
        "brightness" => 70,
        "rippleLightToggle" => "1",
        "sideLightToggle" => 0,
        "bottomLightToggle" => "",
        "unknownToggle" => 1
      }

      assert Messages.device_telemetry(
               map,
               ~w[rippleLightToggle sideLightToggle bottomLightToggle]
             ) ==
               {:ok,
                %{
                  on: true,
                  reachable: true,
                  brightness: 70,
                  zone_states: %{"rippleLightToggle" => true, "sideLightToggle" => false}
                }}
    end

    test "an unreachable lamp is never on" do
      for online <- [false, 0, "false"] do
        assert {:ok, %{on: false, reachable: false}} =
                 Messages.device_telemetry(%{"online" => online, "powerSwitch" => 1}, [])
      end
    end

    test "a missing online flag means reachable; numbers may come as strings" do
      assert {:ok, %{on: true, reachable: true}} =
               Messages.device_telemetry(%{"powerSwitch" => "1"}, [])

      assert {:ok, %{on: false}} = Messages.device_telemetry(%{"powerSwitch" => "on"}, [])
      assert {:ok, %{on: false}} = Messages.device_telemetry(%{"powerSwitch" => [1]}, [])
    end

    test "a colour wins over the colour temperature, which counts only when positive" do
      assert {:ok, %{color: %{r: 255, g: 128, b: 1}} = colour} =
               Messages.device_telemetry(
                 %{"colorRgb" => 0xFF8001, "colorTemperatureK" => 2700},
                 []
               )

      refute Map.has_key?(colour, :color_temp_k)

      assert {:ok, %{color_temp_k: 2700} = white} =
               Messages.device_telemetry(%{"colorRgb" => 0, "colorTemperatureK" => "2700"}, [])

      refute Map.has_key?(white, :color)

      assert {:ok, bare} = Messages.device_telemetry(%{"colorTemperatureK" => 0}, [])
      refute Map.has_key?(bare, :color_temp_k)
    end

    test "an out of range brightness does not coerce" do
      assert Messages.device_telemetry(%{"brightness" => 250}, []) == :error
    end
  end

  describe "set/1" do
    test "one verb per message" do
      assert Messages.set(%{"power" => "on"}) == {:ok, {:power, true}}
      assert Messages.set(%{"power" => false}) == {:ok, {:power, false}}
      assert Messages.set(%{"brightness" => "40"}) == {:ok, {:brightness, 40}}

      assert Messages.set(%{"color" => %{"r" => 1, "g" => 2, "b" => 3}}) ==
               {:ok, {:color, %{r: 1, g: 2, b: 3}}}

      assert Messages.set(%{"color_temp_k" => 4000}) == {:ok, {:color_temp, 4000}}

      assert Messages.set(%{"zone" => %{"name" => "sideLightToggle", "on" => "true"}}) ==
               {:ok, {:zone, "sideLightToggle", true}}

      assert Messages.set(%{"scene" => "Forest"}) == {:ok, {:scene, "Forest"}}
      assert Messages.set(%{power: "off"}) == {:ok, {:power, false}}
      assert Messages.set(%{"zone" => %{name: "z", on: false}}) == {:ok, {:zone, "z", false}}
    end

    test "an unknown verb is nil, a broken one an error" do
      assert Messages.set(%{"dance" => true}) == {:ok, nil}
      assert Messages.set(%{}) == {:ok, nil}

      for bad <- [
            %{"power" => "maybe"},
            %{"brightness" => 101},
            %{"color" => %{"r" => 1}},
            %{"color_temp_k" => "warm"},
            %{"zone" => "sideLightToggle"},
            %{"zone" => %{"name" => "", "on" => true}},
            %{"zone" => %{"name" => "z"}},
            %{"scene" => ""}
          ],
          do: assert(Messages.set(bad) == :error, inspect(bad))

      assert Messages.set("power") == :error
    end

    test "every verb's wire object parses back to it" do
      for verb <- [
            {:power, true},
            {:power, false},
            {:brightness, 1},
            {:color, %{r: 0, g: 10, b: 255}},
            {:color_temp, 6500},
            {:zone, "powerSwitch", true},
            {:scene, "Rock & <Roll>"}
          ] do
        wire = verb |> Messages.set_wire() |> JSON.encode!() |> JSON.decode!()
        assert Messages.set(wire) == {:ok, verb}
      end

      assert JSON.encode!(Messages.set_wire({:power, true})) == ~s({"power":"on"})
    end
  end
end
