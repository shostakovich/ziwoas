defmodule Ziwoas.Govee.DeviceRegistryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ziwoas.Govee.{Device, DeviceRegistry}

  @mac "14:AB:DB:48:44:06:4B:60"
  @key "14ABDB4844064B60"

  defp raw(attrs \\ %{}) do
    Map.merge(
      %{
        "device" => @mac,
        "sku" => "H60B0",
        "deviceName" => "Uplighter",
        "capabilities" => [
          %{"instance" => "powerSwitch"},
          %{"instance" => "brightness"},
          %{"instance" => "colorRgb"},
          %{
            "instance" => "colorTemperatureK",
            "parameters" => %{"range" => %{"min" => 2200, "max" => 6500}}
          },
          %{"instance" => "segmentedColorRgb"},
          %{"instance" => "rippleLightToggle"},
          %{"instance" => "sideLightToggle"},
          %{"instance" => "rippleLightToggle"},
          %{"instance" => "dreamViewToggle"}
        ]
      },
      attrs
    )
  end

  defp no_scenes, do: fn _raw -> {:ok, []} end

  defp refresh(raws, registry \\ DeviceRegistry.new(), scenes \\ no_scenes()),
    do: DeviceRegistry.refresh(registry, raws, scenes)

  test "a MAC becomes a key whatever its separators" do
    assert DeviceRegistry.normalize_mac(@mac) == @key
    assert DeviceRegistry.normalize_mac("14-ab-db 48.44:06:4b:60") == @key
  end

  test "a lamp is curated from the API's device list" do
    assert [%Device{} = device] = DeviceRegistry.all(refresh([raw()]))

    assert device == %Device{
             key: @key,
             api_id: @mac,
             sku: "H60B0",
             name: "Uplighter",
             ip: nil,
             supports_color: true,
             supports_color_temp: true,
             color_temp_min_k: 2200,
             color_temp_max_k: 6500,
             zones: ["rippleLightToggle", "sideLightToggle"],
             scenes: [],
             scene_index: %{},
             power_only: false
           }
  end

  test "a lamp without colour temperature has no range" do
    [device] =
      DeviceRegistry.all(
        refresh([
          raw(%{
            "capabilities" => [%{"instance" => "powerSwitch"}, %{"instance" => "brightness"}]
          })
        ])
      )

    refute device.supports_color or device.supports_color_temp
    assert {device.color_temp_min_k, device.color_temp_max_k, device.zones} == {nil, nil, []}
  end

  test "a configured name wins over Govee's, a blank one does not" do
    registry = DeviceRegistry.new(%{"14-ab-db-48-44-06-4b-60" => "Stehlampe"})
    assert [%{name: "Stehlampe"}] = DeviceRegistry.all(refresh([raw()], registry))

    registry = DeviceRegistry.new(%{@mac => "  "})
    assert [%{name: "Uplighter"}] = DeviceRegistry.all(refresh([raw()], registry))
  end

  test "scenes become names plus an index of their ids" do
    scenes = fn %{"device" => @mac} ->
      {:ok,
       [
         %{"name" => "Forest", "value" => %{"id" => 1, "paramId" => 10}},
         %{"name" => "", "value" => %{"id" => 2}},
         %{"value" => %{"id" => 3}},
         %{"name" => "Aurora", "value" => "broken"}
       ]}
    end

    [device] = DeviceRegistry.all(refresh([raw()], DeviceRegistry.new(), scenes))

    assert device.scenes == ["Forest", "Aurora"]

    assert device.scene_index == %{
             "Forest" => %{id: 1, param_id: 10},
             "Aurora" => %{id: nil, param_id: nil}
           }
  end

  test "failing scenes leave the lamp without scenes" do
    log =
      capture_log(fn ->
        [device] =
          DeviceRegistry.all(
            refresh([raw()], DeviceRegistry.new(), fn _ -> {:error, "HTTP 429"} end)
          )

        assert device.scenes == []
      end)

    assert log =~ "HTTP 429"
  end

  test "a power-only plug is no lamp with scenes, and its scenes are never asked for" do
    scenes = fn _raw -> flunk("scenes asked for a power-only device") end
    power_only = raw(%{"capabilities" => [%{"instance" => "powerSwitch"}]})

    assert [%Device{power_only: true, scenes: []}] =
             DeviceRegistry.all(refresh([power_only], DeviceRegistry.new(), scenes))
  end

  test "devices without an id and Govee's virtual scene devices are left out" do
    raws = [
      raw(%{"device" => nil}),
      raw(%{"device" => ""}),
      raw(%{"device" => "AA:BB", "sku" => "DreamViewScenic"}),
      raw(%{"device" => "CC:DD", "capabilities" => "none"})
    ]

    assert [%Device{key: "CCDD", zones: [], power_only: false}] =
             DeviceRegistry.all(refresh(raws))
  end

  test "a repeated device keeps its first place and its last version" do
    raws = [
      raw(%{"deviceName" => "Erst"}),
      raw(%{"device" => "AA:BB", "deviceName" => "Andere"}),
      raw(%{"deviceName" => "Zuletzt"})
    ]

    assert Enum.map(DeviceRegistry.all(refresh(raws)), & &1.name) == ["Zuletzt", "Andere"]
  end

  test "LAN discovery records the IP by MAC, and a refresh keeps it" do
    registry = refresh([raw(), raw(%{"device" => "AA:BB"})])
    registry = DeviceRegistry.record_lan_ip(registry, "14ab.db48.4406.4b60", "10.0.0.5")

    assert %Device{ip: "10.0.0.5"} = DeviceRegistry.find(registry, @key)
    assert %Device{key: @key} = DeviceRegistry.find_by_ip(registry, "10.0.0.5")
    assert %Device{ip: nil} = DeviceRegistry.find(registry, "AABB")

    registry = refresh([raw(%{"deviceName" => "Neu"})], registry)
    assert [%Device{name: "Neu", ip: "10.0.0.5"}] = DeviceRegistry.all(registry)
  end

  test "an IP for an unknown MAC and lookups that miss change nothing" do
    registry = refresh([raw()])
    assert DeviceRegistry.record_lan_ip(registry, "FF:FF", "10.0.0.9") == registry
    assert DeviceRegistry.find(registry, "FFFF") == nil
    assert DeviceRegistry.find_by_ip(registry, "10.0.0.9") == nil
  end
end
