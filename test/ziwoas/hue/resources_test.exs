defmodule Ziwoas.Hue.ResourcesTest do
  use ExUnit.Case, async: true

  import Ziwoas.HueFixtures

  alias Ziwoas.Hue.Resources

  defp index, do: Resources.index(resources())

  test "keeps lights, devices and Zigbee connections, nothing else" do
    kinds = index() |> Map.values() |> Enum.map(& &1["type"]) |> Enum.uniq() |> Enum.sort()
    assert kinds == ["device", "light", "zigbee_connectivity"]
    assert Resources.kept?(%{"type" => "light"})
    refute Resources.kept?(%{"type" => "button"})
    refute Resources.kept?(%{})
  end

  test "a device with two light services is two lamps, each with its own controls" do
    lamps = Map.new(Resources.lamps(index()), &{&1.name, &1})

    assert Map.keys(lamps) |> Enum.sort() ==
             ["Farblicht", "Kerzenlampe", "Twilight Back", "Twilight Front"]

    assert lamps["Twilight Back"].key == key(twilight_back())
    assert lamps["Twilight Front"].key == key(twilight_front())

    for name <- ["Twilight Back", "Twilight Front"] do
      assert %{supports_color: true, supports_color_temp: true, color_temp_max_k: 6536} =
               lamps[name]

      assert "fire" in lamps[name].scenes
      assert lamps[name].sku == "LGT001"
    end
  end

  test "a light's state follows its device's Zigbee connection" do
    assert %{on: true, reachable: true} = Resources.state(index(), candle())
    assert %{on: false, reachable: false} = Resources.state(index(), colour_only())
  end

  test "a light without a device counts as reachable" do
    resources = %{"l1" => %{"id" => "l1", "type" => "light", "on" => %{"on" => true}}}
    assert %{on: true, reachable: true} = Resources.state(resources, "l1")
    assert Resources.reachable?(resources, "l1")
  end

  test "a light is reachable while its device's Zigbee connection is connected" do
    assert Resources.reachable?(index(), candle())
    refute Resources.reachable?(index(), colour_only())
  end

  test "skips what is no resource, and a device's malformed services" do
    light = %{"id" => "l1", "type" => "light", "metadata" => "none", "owner" => %{"rid" => "d1"}}
    device = %{"id" => "d1", "type" => "device", "services" => "none"}
    index = Resources.index(["x", %{"id" => 1, "type" => "light"}, light, device])

    assert Map.keys(index) == ["d1", "l1"]
    assert [%{key: "l1", name: nil, sku: nil}] = Resources.lamps(index)
  end

  describe "an update" do
    test "merges into the light and names it" do
      {resources, touched} =
        Resources.update(index(), [
          %{"id" => candle(), "type" => "light", "dimming" => %{"brightness" => 20.0}}
        ])

      assert touched == [candle()]
      assert %{brightness: 20, color_temp_k: 2703} = Resources.state(resources, candle())
      assert resources[candle()]["dimming"]["min_dim_level"] == 2.0
    end

    test "of a Zigbee connection touches every light of its device" do
      {resources, touched} =
        Resources.update(index(), [
          %{
            "id" => "00000003-0000-4000-8000-000000000003",
            "type" => "zigbee_connectivity",
            "status" => "connectivity_issue"
          }
        ])

      assert Enum.sort(touched) == Enum.sort([twilight_back(), twilight_front()])
      assert %{reachable: false} = Resources.state(resources, twilight_front())
    end

    test "of a device touches its lights, of an unknown resource nothing" do
      device = %{"id" => "00000008-0000-4000-8000-000000000008", "type" => "device"}
      assert {_resources, [id]} = Resources.update(index(), [device])
      assert id == candle()

      assert {resources, []} = Resources.update(index(), [%{"id" => "x", "type" => "light"}])
      assert resources == index()

      assert Resources.update(index(), ["x", 3, %{"type" => "light"}]) == {index(), []}

      button = %{"id" => "b", "type" => "button", "owner" => %{"rid" => "nope"}}
      assert {_resources, []} = Resources.update(Map.put(index(), "b", button), [button])
    end
  end
end
