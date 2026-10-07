defmodule Ziwoas.LightsTest do
  use Ziwoas.DataCase

  alias Ziwoas.Lights
  alias Ziwoas.Lights.{Light, State}
  alias Ziwoas.Repo

  @lamp %{
    key: "K",
    name: "Uplighter",
    sku: "H60B0",
    supports_color: true,
    supports_color_temp: true,
    color_temp_min_k: 2200,
    color_temp_max_k: 6500,
    zones: ["rippleLightToggle"],
    scenes: []
  }

  describe "put_lamp/1" do
    test "a lamp the bridge reports becomes a light; empty lists are NULL" do
      assert {:ok, %Light{}} = Lights.put_lamp(@lamp)

      assert [
               %Light{
                 key: "K",
                 name: "Uplighter",
                 sku: "H60B0",
                 supports_color: true,
                 color_temp_min_k: 2200,
                 zones: ["rippleLightToggle"],
                 firmware_scenes: nil
               }
             ] = Repo.all(Light)
    end

    test "a later report keeps the stored name and leaves an unchanged row alone" do
      stamp = ~U[2026-01-01 00:00:00.000000Z]
      Lights.put_lamp(%{@lamp | name: "Uplighter"})
      Repo.update_all(Light, set: [name: "Mein Name", updated_at: stamp])

      assert {:ok, %Light{}} = Lights.put_lamp(@lamp)
      assert [%Light{name: "Mein Name", updated_at: ^stamp}] = Repo.all(Light)
    end

    test "a blank name falls back to the key; a key with separators is refused" do
      Lights.put_lamp(%{@lamp | name: " "})
      assert [%Light{name: "K"}] = Repo.all(Light)

      assert Lights.put_lamp(%{@lamp | key: "14:AB"}) == {:error, :invalid}
      assert Repo.aggregate(Light, :count) == 1
    end

    test "a lamp whose values do not fit is refused" do
      assert {:error, %Ecto.Changeset{}} = Lights.put_lamp(%{@lamp | color_temp_min_k: "warm"})
      assert Repo.all(Light) == []
    end
  end

  describe "put_state/2" do
    test "records power, readings and zone bits, merged into the stored zones" do
      Repo.insert!(%State{light_key: "K", zone_states: %{"sideLightToggle" => true}})

      Lights.put_state("K", %{
        on: true,
        reachable: true,
        brightness: 55,
        color: %{r: 1, g: 2, b: 3},
        zone_states: %{"rippleLightToggle" => true}
      })

      assert %State{
               on: true,
               reachable: true,
               brightness: 55,
               color_r: 1,
               color_g: 2,
               color_b: 3,
               zone_states: %{"rippleLightToggle" => true, "sideLightToggle" => true}
             } = Repo.get_by(State, light_key: "K")
    end

    test "an absent reading stays untouched" do
      Repo.insert!(%State{light_key: "K", brightness: 40, color_temp_k: 2700})
      Lights.put_state("K", %{on: false, reachable: false})

      assert %State{on: false, reachable: false, brightness: 40, color_temp_k: 2700} =
               Repo.get_by(State, light_key: "K")
    end

    test "a reading that does not fit is refused and tells nobody" do
      Lights.subscribe()

      assert {:error, %Ecto.Changeset{}} =
               Lights.put_state("K", %{on: true, reachable: true, brightness: "hell"})

      assert Repo.all(State) == []
      refute_received {:updated, _}
    end

    test "tells the subscribers of all lamps and of that lamp" do
      Lights.subscribe()
      Lights.subscribe("BCAST")
      Lights.subscribe("OTHER")

      Lights.put_state("BCAST", %{on: false, reachable: true})

      assert_received {:updated, "BCAST"}
      assert_received {:updated, "BCAST"}
      refute_received {:updated, _}
    end
  end

  test "zones carry their role, main zones first" do
    light = %Light{key: "Z", zones: ~w[rippleLightToggle bottomLightToggle powerSwitch]}
    state = %State{light_key: "Z", zone_states: %{"rippleLightToggle" => true}}

    assert Lights.zones(%Lights.Snapshot{light: light, state: state}) == [
             %Lights.Zone{key: "bottomLightToggle", role: :main, on: false},
             %Lights.Zone{key: "rippleLightToggle", role: :side, on: true}
           ]
  end
end
