defmodule Ziwoas.Govee.CommandRouterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ziwoas.Govee.{CommandRouter, Device, StateStore}

  @key "AABBCC"

  defp device(attrs \\ []) do
    struct!(
      %Device{key: @key, api_id: "AA:BB:CC", sku: "H6008", name: "Lampe", ip: "10.0.0.5"},
      attrs
    )
  end

  # The two effects as messages to the test.
  defp io do
    test = self()
    %{lan: &send(test, {:lan, &1}), api: &send(test, {:api, &1})}
  end

  defp handle(device, verb, store \\ StateStore.new(5.0)),
    do: CommandRouter.handle(device, @key, verb, store, io(), 10.0)

  defp effects do
    receive do
      {kind, effect} when kind in [:lan, :api] -> [{kind, effect} | effects()]
    after
      0 -> []
    end
  end

  defp api(type, instance, value),
    do:
      {:api,
       [
         sku: "H6008",
         device: "AA:BB:CC",
         type: "devices.capabilities.#{type}",
         instance: instance,
         value: value
       ]}

  describe "with a LAN address" do
    test "power goes over the LAN and asks for the status" do
      {published, store} = handle(device(), %{"power" => "on"})

      assert published == %{on: true}
      assert StateStore.status(store, @key) == :pending

      assert effects() == [
               {:lan, {:turn, "10.0.0.5", true}},
               {:lan, {:request_status, "10.0.0.5"}}
             ]
    end

    test "brightness, colour and white too, each also switching the lamp on" do
      assert {%{on: true, brightness: 30}, _} = handle(device(), %{"brightness" => 30})

      assert effects() == [
               {:lan, {:brightness, "10.0.0.5", 30}},
               {:lan, {:request_status, "10.0.0.5"}}
             ]

      assert {%{on: true, color: %{r: 1, g: 2, b: 3}, color_temp_k: nil}, _} =
               handle(device(), %{"color" => %{"r" => 1, "g" => 2, "b" => 3}})

      assert [{:lan, {:color, "10.0.0.5", %{r: 1, g: 2, b: 3}}}, _status] = effects()

      assert {%{on: true, color_temp_k: 4000, color: nil}, _} =
               handle(device(), %{"color_temp_k" => 4000})

      assert [{:lan, {:color_temp, "10.0.0.5", 4000}}, _status] = effects()
    end

    test "a power-only lamp still goes through the API" do
      handle(device(power_only: true), %{"power" => "off"})
      assert effects() == [api("on_off", "powerSwitch", 0)]
    end
  end

  describe "without a LAN address" do
    test "power, brightness, colour and white go through the API" do
      lamp = device(ip: nil)

      handle(lamp, %{"power" => true})
      handle(lamp, %{"brightness" => "55"})
      handle(lamp, %{"color" => %{"r" => 255, "g" => 128, "b" => 1}})
      handle(lamp, %{"color_temp_k" => 2700})

      assert effects() == [
               api("on_off", "powerSwitch", 1),
               api("range", "brightness", 55),
               api("color_setting", "colorRgb", 0xFF8001),
               api("color_setting", "colorTemperatureK", 2700)
             ]
    end
  end

  describe "zones and scenes are API-only" do
    test "a zone merges its bit into the published zones" do
      {_published, store} =
        StateStore.record_command(StateStore.new(5.0), @key, %{zone_states: %{"a" => true}}, 0.0)

      {published, _store} = handle(device(), %{"zone" => %{"name" => "b", "on" => false}}, store)

      assert published == %{zone_states: %{"a" => true, "b" => false}}
      assert effects() == [api("toggle", "b", 0)]
    end

    test "the powerSwitch zone keeps the lamp's power in step" do
      {published, _store} =
        handle(device(), %{"zone" => %{"name" => "powerSwitch", "on" => true}})

      assert published == %{on: true, zone_states: %{"powerSwitch" => true}}
    end

    test "a known scene sends its ids" do
      lamp = device(scene_index: %{"Forest" => %{id: 7, param_id: 99}})
      assert {%{on: true}, _store} = handle(lamp, %{"scene" => "Forest"})
      assert effects() == [api("dynamic_scene", "lightScene", %{"id" => 7, "paramId" => 99})]
    end

    test "an unknown scene sends and publishes nothing" do
      store = StateStore.new(5.0)

      log =
        capture_log(fn ->
          assert handle(device(), %{"scene" => "Disco"}, store) == {nil, store}
        end)

      assert log =~ "unknown scene 'Disco'"
      assert effects() == []
    end
  end

  describe "what is not routed" do
    test "an unknown lamp" do
      store = StateStore.new(5.0)

      log =
        capture_log(fn ->
          assert CommandRouter.handle(nil, @key, %{"power" => "on"}, store, io(), 0.0) ==
                   {nil, store}
        end)

      assert log =~ "unknown device #{@key}"
      assert effects() == []
    end

    test "an unknown verb" do
      store = StateStore.new(5.0)
      log = capture_log(fn -> assert handle(device(), %{"dance" => 1}, store) == {nil, store} end)
      assert log =~ "unknown verb"
      assert effects() == []
    end

    test "a verb that does not coerce" do
      assert handle(device(), %{"brightness" => 101}) == {:error, :invalid}
      assert handle(device(), %{"power" => "maybe"}) == {:error, :invalid}
      assert effects() == []
    end
  end

  test "a failing effect raises to the caller and records nothing" do
    failing = %{lan: fn _ -> raise "socket closed" end, api: fn _ -> raise "HTTP 500" end}
    store = StateStore.new(5.0)

    assert_raise RuntimeError, "socket closed", fn ->
      CommandRouter.handle(device(), @key, %{"power" => "on"}, store, failing, 0.0)
    end

    assert_raise RuntimeError, "HTTP 500", fn ->
      CommandRouter.handle(device(ip: nil), @key, %{"power" => "on"}, store, failing, 0.0)
    end
  end
end
