defmodule Ziwoas.Govee.CommandRouterTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Govee.{CommandRouter, Device}

  defp device(attrs \\ []) do
    struct!(
      %Device{key: "AABBCC", api_id: "AA:BB:CC", sku: "H6008", name: "Lampe", ip: "10.0.0.5"},
      attrs
    )
  end

  defp api(type, instance, value),
    do:
      {:ok,
       {:api,
        [
          sku: "H6008",
          device: "AA:BB:CC",
          type: "devices.capabilities.#{type}",
          instance: instance,
          value: value
        ]}}

  defp lan(command), do: {:ok, {:lan, [command, {:request_status, "10.0.0.5"}]}}

  describe "with a LAN address" do
    test "power, brightness, colour and white go over the LAN and ask for the status" do
      assert CommandRouter.route(device(), {:power, true}) == lan({:turn, "10.0.0.5", true})

      assert CommandRouter.route(device(), {:brightness, 30}) ==
               lan({:brightness, "10.0.0.5", 30})

      assert CommandRouter.route(device(), {:color, %{r: 1, g: 2, b: 3}}) ==
               lan({:color, "10.0.0.5", %{r: 1, g: 2, b: 3}})

      assert CommandRouter.route(device(), {:color_temp, 4000}) ==
               lan({:color_temp, "10.0.0.5", 4000})
    end

    test "a power-only lamp still goes through the API" do
      assert CommandRouter.route(device(power_only: true), {:power, false}) ==
               api("on_off", "powerSwitch", 0)
    end
  end

  test "without a LAN address power, brightness, colour and white go through the API" do
    lamp = device(ip: nil)

    assert CommandRouter.route(lamp, {:power, true}) == api("on_off", "powerSwitch", 1)
    assert CommandRouter.route(lamp, {:brightness, 55}) == api("range", "brightness", 55)

    assert CommandRouter.route(lamp, {:color, %{r: 255, g: 128, b: 1}}) ==
             api("color_setting", "colorRgb", 0xFF8001)

    assert CommandRouter.route(lamp, {:color_temp, 2700}) ==
             api("color_setting", "colorTemperatureK", 2700)
  end

  describe "zones and scenes are API-only" do
    test "a zone toggles its instance" do
      assert CommandRouter.route(device(), {:zone, "b", false}) == api("toggle", "b", 0)
    end

    test "a known scene sends its ids, an unknown one nothing" do
      lamp = device(scene_index: %{"Forest" => %{id: 7, param_id: 99}})

      assert CommandRouter.route(lamp, {:scene, "Forest"}) ==
               api("dynamic_scene", "lightScene", %{"id" => 7, "paramId" => 99})

      assert CommandRouter.route(lamp, {:scene, "Disco"}) == {:error, :unknown_scene}
    end
  end

  describe "changes" do
    test "brightness, colour and white switch the lamp on; colour and white clear each other" do
      assert CommandRouter.changes({:power, false}, nil) == %{on: false}
      assert CommandRouter.changes({:brightness, 30}, nil) == %{on: true, brightness: 30}

      assert CommandRouter.changes({:color, %{r: 1, g: 2, b: 3}}, nil) ==
               %{on: true, color: %{r: 1, g: 2, b: 3}, color_temp_k: nil}

      assert CommandRouter.changes({:color_temp, 4000}, nil) ==
               %{on: true, color_temp_k: 4000, color: nil}

      assert CommandRouter.changes({:scene, "Forest"}, nil) == %{on: true}
    end

    test "a zone merges its bit into the published zones" do
      assert CommandRouter.changes({:zone, "b", false}, %{zone_states: %{"a" => true}}) ==
               %{zone_states: %{"a" => true, "b" => false}}
    end

    test "the powerSwitch zone keeps the lamp's power in step" do
      assert CommandRouter.changes({:zone, "powerSwitch", true}, nil) ==
               %{on: true, zone_states: %{"powerSwitch" => true}}
    end
  end
end
