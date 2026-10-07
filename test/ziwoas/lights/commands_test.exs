defmodule Ziwoas.Lights.CommandsTest do
  # Mirrors test/models/lights/operations/*_test.rb and the commander half of
  # test/lib/govees/commander_test.rb.
  use Ziwoas.DataCase, async: true

  alias Ziwoas.{Clock, Mqtt, Ownership, Repo}
  alias Ziwoas.Lights.{Commands, Light, State}

  setup %{repo: repo} do
    Clock.freeze("2026-06-15T18:00:00Z")
    Repo.put_writer(:main, repo)
    Ownership.override(%{lights: :phoenix})
    on_exit(&Ownership.clear_override/0)
    record(:ok)
  end

  defp record(answer) do
    test = self()

    Mqtt.record(fn _client, topic, payload ->
      send(test, {:published, topic, payload})
      answer
    end)
  end

  defp light!(attrs), do: Repo.insert!(struct!(%Light{name: "L"}, attrs))
  defp state(key), do: Repo.get_by(State, light_key: key)

  defp sent do
    receive do
      {:published, topic, payload} -> [{topic, payload} | sent()]
    after
      0 -> []
    end
  end

  describe "turn" do
    test "a simple lamp gets the power verb; the state is recorded; the hero redraws" do
      light!(%{key: "S1", zones: []})
      assert {:ok, :power} = Commands.run(light!(%{key: "S0"}), "turn", %{"on" => "true"})
      assert {:ok, :power} = Commands.run(Repo.get_by(Light, key: "S1"), "turn", %{"on" => "off"})

      assert sent() == [
               {"govees/S0/set", ~s({"power":"on"})},
               {"govees/S1/set", ~s({"power":"off"})}
             ]

      assert %State{on: true, zone_states: nil} = state("S0")
      assert %State{on: false} = state("S1")
    end

    test "a zone lamp routes power through powerSwitch" do
      light = light!(%{key: "U1", zones: ~w[bottomLightToggle sideLightToggle]})
      Commands.run(light, "turn", %{"on" => "1"})
      assert sent() == [{"govees/U1/set", ~s({"zone":{"name":"powerSwitch","on":true}})}]
    end

    test "an unchanged state is not written again" do
      light = light!(%{key: "S2"})
      Repo.insert!(%State{light_key: "S2", on: true, updated_at: ~U[2026-01-01 00:00:00.000000Z]})
      Commands.run(light, "turn", %{"on" => "true"})
      assert state("S2").updated_at == ~U[2026-01-01 00:00:00.000000Z]
    end

    test "an uncoercible flag is invalid and sends nothing" do
      light = light!(%{key: "S3"})

      for params <- [%{"on" => ""}, %{"on" => "maybe"}, %{}] do
        assert {:error, :invalid} = Commands.run(light, "turn", params)
      end

      assert sent() == []
    end

    test "a broker failure is a commander failure and records nothing" do
      record({:error, :timeout})
      light = light!(%{key: "S4"})
      assert {:error, :commander} = Commands.run(light, "turn", %{"on" => "true"})
      assert state("S4") == nil
    end
  end

  describe "values" do
    setup do: %{light: light!(%{key: "C1", color_temp_min_k: 2700, color_temp_max_k: 6500})}

    test "brightness, colour, white and scenes are fire and forget", %{light: light} do
      assert {:ok, :no_content} = Commands.run(light, "brightness", %{"value" => " 42 "})

      assert {:ok, :no_content} =
               Commands.run(light, "color", %{"r" => "10", "g" => "20", "b" => "30"})

      assert {:ok, :no_content} = Commands.run(light, "color_temp", %{"temp_k" => "2200"})
      assert {:ok, :no_content} = Commands.run(light, "color_temp", %{"temp_k" => "9000"})
      assert {:ok, :no_content} = Commands.run(light, "effect", %{"effect" => "Forest"})
      assert {:ok, :no_content} = Commands.run(light, "scene", %{"scene" => "Rock & <Roll>"})

      assert sent() == [
               {"govees/C1/set", ~s({"brightness":42})},
               {"govees/C1/set", ~s({"color":{"r":10,"g":20,"b":30}})},
               {"govees/C1/set", ~s({"color_temp_k":2700})},
               {"govees/C1/set", ~s({"color_temp_k":6500})},
               {"govees/C1/set", ~s({"scene":"Forest"})},
               {"govees/C1/set", ~s({"scene":"Rock & <Roll>"})}
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
            {"scene", %{}}
          ] do
        assert {:error, :invalid} = Commands.run(light, command, params),
               "#{command} #{inspect(params)}"
      end

      assert sent() == []
    end
  end

  describe "zones" do
    test "a valid zone is switched and recorded, without a toast" do
      light = light!(%{key: "Z0", zones: ~w[bottomLightToggle rippleLightToggle]})

      assert {:ok, {:zones, ["rippleLightToggle"], nil}} =
               Commands.run(light, "zone", %{"zone" => "rippleLightToggle", "on" => "true"})

      assert sent() == [{"govees/Z0/set", ~s({"zone":{"name":"rippleLightToggle","on":true}})}]
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
               {"govees/Z1/set", ~s({"zone":{"name":"rippleLightToggle","on":false}})},
               {"govees/Z1/set", ~s({"zone":{"name":"sideLightToggle","on":true}})}
             ]

      assert state("Z1").zone_states ==
               %{
                 "bottomLightToggle" => true,
                 "rippleLightToggle" => false,
                 "sideLightToggle" => true
               }
    end

    test "the stored key order is kept and a new key appended, as Ruby's Hash#merge" do
      light!(%{key: "Z4", zones: ~w[mainLightToggle backgroundLightToggle]})

      Repo.insert!(%State{light_key: "Z4"})
      Repo.query!(~s(UPDATE light_states SET zone_states = '{"mainLightToggle":true}'))
      Commands.record_zone_state("Z4", "backgroundLightToggle", false)
      Commands.record_zone_state("Z4", "mainLightToggle", false)

      assert %{rows: [[~s({"mainLightToggle":false,"backgroundLightToggle":false})]]} =
               Repo.query!("SELECT zone_states FROM light_states")
    end

    test "a commander failure leaves the stored zones alone" do
      record({:error, :closed})
      light = light!(%{key: "K", sku: "H60B0", zones: ~w[rippleLightToggle sideLightToggle]})
      Repo.insert!(%State{light_key: "K", zone_states: %{}})

      assert {:error, :commander} =
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

  test "the command names are Rails' Lights::Operations" do
    for name <- ~w[turn zone brightness color color_temp effect scene zone_undo],
        do: assert(Commands.command?(name))

    refute Commands.command?("explode")
    refute Commands.command?(["turn"])
  end

  test "a dry run sends nothing and records the state in the shadow database" do
    Ownership.override(%{lights: :dry_run})
    Repo.put_writer(:shadow, Repo.get_dynamic_repo())
    light = light!(%{key: "D1"})
    assert {:ok, :power} = Commands.run(light, "turn", %{"on" => "true"})
    assert sent() == []
    assert %State{on: true} = state("D1")
  end
end
