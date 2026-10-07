defmodule Ziwoas.Govee.PlatformApiTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Govee.PlatformApi

  describe "telemetry/2" do
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

      assert PlatformApi.telemetry(
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
                 PlatformApi.telemetry(%{"online" => online, "powerSwitch" => 1}, [])
      end
    end

    test "a missing online flag means reachable; numbers may come as strings" do
      assert {:ok, %{on: true, reachable: true}} =
               PlatformApi.telemetry(%{"powerSwitch" => "1"}, [])

      assert {:ok, %{on: false}} = PlatformApi.telemetry(%{"powerSwitch" => "on"}, [])
      assert {:ok, %{on: false}} = PlatformApi.telemetry(%{"powerSwitch" => [1]}, [])
    end

    test "a colour wins over the colour temperature, which counts only when positive" do
      assert {:ok, %{color: %{r: 255, g: 128, b: 1}} = colour} =
               PlatformApi.telemetry(
                 %{"colorRgb" => 0xFF8001, "colorTemperatureK" => 2700},
                 []
               )

      refute Map.has_key?(colour, :color_temp_k)

      assert {:ok, %{color_temp_k: 2700} = white} =
               PlatformApi.telemetry(%{"colorRgb" => 0, "colorTemperatureK" => "2700"}, [])

      refute Map.has_key?(white, :color)

      assert {:ok, bare} = PlatformApi.telemetry(%{"colorTemperatureK" => 0}, [])
      refute Map.has_key?(bare, :color_temp_k)
    end

    test "an out of range brightness does not coerce" do
      assert PlatformApi.telemetry(%{"brightness" => 250}, []) == :error
    end
  end

  describe "errors" do
    defp api(status, body),
      do:
        PlatformApi.new("k",
          plug: fn conn -> Plug.Conn.send_resp(conn, status, body) end
        )

    test "the HTTP status, the body's code and broken JSON are reasons, not text" do
      assert PlatformApi.devices(api(503, "")) == {:error, {:http_status, 503}}

      assert PlatformApi.devices(api(200, ~s({"code":429,"message":"too many"}))) ==
               {:error, {:api, 429, "too many"}}

      assert PlatformApi.devices(api(200, "nope")) == {:error, :invalid_json}
    end
  end
end
