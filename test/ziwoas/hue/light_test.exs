defmodule Ziwoas.Hue.LightTest do
  use ExUnit.Case, async: true

  import Ziwoas.HueFixtures

  alias Ziwoas.Hue.Light

  test "a lamp is keyed by its light service without hyphens, and back" do
    assert Light.key(candle()) == "0000000a000040008000" <> "00000000000a"
    assert Light.id(Light.key(candle())) == candle()
    assert Light.id("not-a-key") == "not-a-key"
  end

  describe "the lamp a light is" do
    test "white with its kelvin range and effects, without colour" do
      assert Light.lamp(resource(candle()), "Kerzenlampe") == %{
               key: key(candle()),
               vendor: :hue,
               name: "Kerzenlampe",
               supports_color: false,
               supports_color_temp: true,
               color_temp_min_k: 2203,
               color_temp_max_k: 6536,
               scenes: ["no_effect", "candle", "sparkle", "glisten"]
             }
    end

    test "colour without white, and without effects" do
      lamp = Light.lamp(resource(colour_only()), "Farblicht")

      assert %{supports_color: true, supports_color_temp: false, scenes: []} = lamp
      assert %{color_temp_min_k: nil, color_temp_max_k: nil} = lamp
    end

    test "effects from the older field, and none when only no_effect is left" do
      light = %{"effects" => %{"effect_values" => ["no_effect", "fire"]}}
      assert Light.effects(light) == ["no_effect", "fire"]
      assert Light.effects(%{"effects" => %{"effect_values" => ["no_effect"]}}) == []
    end
  end

  describe "a light the bridge describes badly" do
    test "without a usable mirek range does no white" do
      for schema <- [%{}, %{"mirek_minimum" => 0, "mirek_maximum" => 500}, "none"] do
        light = put_in(resource(candle()), ["color_temperature", "mirek_schema"], schema)

        assert %{supports_color_temp: false, color_temp_min_k: nil, color_temp_max_k: nil} =
                 Light.lamp(light, "Kerzenlampe")

        assert Light.update(light, {:color_temp, 2700}) == {:error, :unsupported}
      end
    end

    test "with a colour that is no point reports none" do
      light = put_in(resource(colour_only()), ["color", "xy"], %{"x" => "a", "y" => nil})
      refute Map.has_key?(Light.state(light, true), :color)
    end

    test "with a gamut that is no triangle takes the colour as it is" do
      for gamut <- [%{"red" => %{"x" => 0.7}}, "none", flat_gamut()] do
        light = put_in(resource(colour_only()), ["color", "gamut"], gamut)

        assert {:ok, %{"color" => %{"xy" => _xy}}} =
                 Light.update(light, {:color, %{r: 0, g: 255, b: 0}})
      end
    end

    test "with effects that are no list has none" do
      assert Light.effects(%{"effects_v2" => %{"action" => %{"effect_values" => "candle"}}}) == []
      assert Light.effects(%{"effects_v2" => "none"}) == []
    end
  end

  defp flat_gamut do
    point = %{"x" => 0.3, "y" => 0.3}
    %{"red" => point, "green" => point, "blue" => %{"x" => 0.2, "y" => 0.1}}
  end

  describe "the state a light reports" do
    test "on, brightness rounded and white in kelvin" do
      assert Light.state(resource(candle()), true) ==
               %{on: true, reachable: true, brightness: 70, color_temp_k: 2703}
    end

    test "a colour drops the white" do
      assert %{color_temp_k: nil, color: %{r: 255, g: g, b: b}} =
               Light.state(resource(colour_only()), true)

      assert g in 100..200 and b < g
    end

    test "unreachable is off, and a faint lamp is at least 1 %" do
      light = Map.put(resource(candle()), "dimming", %{"brightness" => 0.4})
      assert %{on: false, reachable: false, brightness: 1} = Light.state(light, false)
    end

    test "a light without dimming or colour has only its power" do
      assert Light.state(%{"on" => %{"on" => false}}, true) == %{on: false, reachable: true}
    end
  end

  describe "the update for a verb" do
    test "power and brightness" do
      assert Light.update(resource(candle()), {:power, false}) ==
               {:ok, %{"on" => %{"on" => false}}}

      assert Light.update(resource(candle()), {:brightness, 40}) ==
               {:ok, %{"on" => %{"on" => true}, "dimming" => %{"brightness" => 40}}}
    end

    test "kelvin becomes mirek within the light's range" do
      assert Light.update(resource(candle()), {:color_temp, 2700}) ==
               {:ok, %{"on" => %{"on" => true}, "color_temperature" => %{"mirek" => 370}}}

      assert {:ok, %{"color_temperature" => %{"mirek" => 454}}} =
               Light.update(resource(candle()), {:color_temp, 1800})
    end

    test "RGB becomes xy inside the light's gamut" do
      assert {:ok, %{"on" => %{"on" => true}, "color" => %{"xy" => %{"x" => x, "y" => y}}}} =
               Light.update(resource(colour_only()), {:color, %{r: 0, g: 255, b: 0}})

      assert {x, y} == {0.2151, 0.7106}
    end

    test "an effect the light offers, through effects_v2 or the older field" do
      assert Light.update(resource(candle()), {:scene, "candle"}) ==
               {:ok,
                %{"on" => %{"on" => true}, "effects_v2" => %{"action" => %{"effect" => "candle"}}}}

      assert Light.update(resource(candle()), {:scene, "no_effect"}) ==
               {:ok, %{"effects_v2" => %{"action" => %{"effect" => "no_effect"}}}}

      older = %{"effects" => %{"effect_values" => ["no_effect", "fire"]}}

      assert Light.update(older, {:scene, "fire"}) ==
               {:ok, %{"on" => %{"on" => true}, "effects" => %{"effect" => "fire"}}}

      assert Light.update(resource(candle()), {:scene, "fire"}) == {:error, :unsupported}
    end

    test "what the light cannot do is unsupported" do
      for verb <- [{:color, %{r: 1, g: 2, b: 3}}, {:zone, "powerSwitch", true}],
          do: assert(Light.update(resource(candle()), verb) == {:error, :unsupported})

      assert Light.update(resource(colour_only()), {:color_temp, 3000}) == {:error, :unsupported}
      assert Light.update(%{"on" => %{"on" => true}}, {:brightness, 10}) == {:error, :unsupported}
    end
  end
end
