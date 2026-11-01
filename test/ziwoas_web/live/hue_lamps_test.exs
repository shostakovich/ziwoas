defmodule ZiwoasWeb.HueLampsTest do
  use ZiwoasWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ziwoas.HueFixtures
  import Ziwoas.LampPower

  alias Ziwoas.{FakeGoveeBridge, FakeShelly, HueStub, Plugs, Repo}
  alias Ziwoas.Lights.{Light, PowerUp}

  @moduletag :shared_sandbox
  @moduletag :capture_log

  setup do
    {_bridge, stub} = HueStub.start_bridge!()
    %{stub: stub}
  end

  defp tile(view, id), do: element(view, "#light_card_#{key(id)} button[aria-pressed]")

  test "a Govee lamp and a Hue lamp side by side, each command reaching its own bridge", %{
    conn: conn
  } do
    start_supervised!({FakeGoveeBridge, test: self()})
    Repo.insert!(%Light{key: "ABCDEF01", name: "Stehlampe", sku: "H607C"})
    {:ok, view, _html} = live(conn, ~p"/switches")

    for name <- ["Stehlampe", "Kerzenlampe", "Twilight Back", "Twilight Front", "Farblicht"],
        do: assert(has_element?(view, "[id^=light_card_]", name))

    assert has_element?(view, "#light_card_#{key(twilight_back())} img[src*='lamp_bedside_']")
    assert has_element?(view, "#light_card_#{key(colour_only())} img[src*='lamp_cone_off']")

    view |> element("#light_card_ABCDEF01 button[aria-pressed]") |> render_click()
    render_async(view)
    assert_received {:govee, "ABCDEF01", {:power, true}}
    refute_received {:hue_put, _id, _body}

    view |> tile(twilight_back()) |> render_click()
    render_async(view)
    back = twilight_back()
    assert_received {:hue_put, ^back, %{"on" => %{"on" => false}}}
    refute_received {:govee, _key, _verb}
  end

  test "both light sources of a Twilight can be given the same plug", %{conn: conn} do
    for id <- [twilight_back(), twilight_front()] do
      {:ok, view, _html} = live(conn, ~p"/lights/#{key(id)}")
      view |> element("#light_settings_open") |> render_click()

      view
      |> form("#light_form", %{"light" => %{"shelly_plug_id" => "fridge"}})
      |> render_submit()
    end

    assert Light |> Repo.all() |> Enum.count(&(&1.shelly_plug_id == "fridge")) == 2
  end

  test "a change in the Hue app shows on the tile and the lamp page without a reload", %{
    conn: conn,
    stub: stub
  } do
    {:ok, tiles, _html} = live(conn, ~p"/switches")
    {:ok, page, _html} = live(conn, ~p"/lights/#{key(candle())}")
    assert has_element?(tiles, "#light_card_#{key(candle())} [data-brightness]", "70 %")

    HueStub.push(stub, [
      update([%{"id" => candle(), "type" => "light", "dimming" => %{"brightness" => 20.0}}])
    ])

    assert has_element?(tiles, "#light_card_#{key(candle())} [data-brightness]", "20 %")
    assert has_element?(page, "#light_brightness_form output", "20 %")
  end

  test "a Hue lamp that only does white offers white but no colour, and its effects", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/lights/#{key(candle())}")

    assert has_element?(view, "#light_panel_white")
    refute has_element?(view, "#light_panel_color")
    assert has_element?(view, "#light_panel_switch button[phx-value-value=scenes]", "Effekte")
    assert has_element?(view, "#light_scenes_label", "Hue-Effekte")
    assert has_element?(view, "#light_panel_scenes button", "Kerze")

    view |> element("#light_panel_scenes button", "Kerze") |> render_click()
    render_async(view)
    candle = candle()

    assert_received {:hue_put, ^candle, %{"effects_v2" => %{"action" => %{"effect" => "candle"}}}}
  end

  test "a Hue lamp's white and colour go to the bridge as mirek and xy", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lights/#{key(twilight_front())}")
    front = twilight_front()

    render_hook(view, "light_command", %{"command" => "color_temp", "temp_k" => "2700"})
    render_async(view)
    assert_received {:hue_put, ^front, %{"color_temperature" => %{"mirek" => 370}}}

    render_hook(view, "light_command", %{
      "command" => "color",
      "r" => "255",
      "g" => "0",
      "b" => "0"
    })

    render_async(view)
    assert_received {:hue_put, ^front, %{"color" => %{"xy" => %{"x" => 0.6915, "y" => 0.3083}}}}
  end

  describe "a Hue lamp on a plug whose relay is off" do
    setup do
      start_power_up!()

      Repo.update_all(from(l in Light, where: l.key == ^key(candle())),
        set: [shelly_plug_id: "fridge"]
      )

      Repo.insert!(%Plugs.State{plug_id: "fridge", output: false})
      :ok
    end

    test "shows unpowered, though the bridge still reports it on", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/switches")

      card = "#light_card_#{key(candle())}"

      assert has_element?(view, "#{card} [data-status]", ~r/Aus\W+stromlos/u)
      assert has_element?(view, "#{card} button[aria-pressed=false][phx-value-on=true]")
    end

    test "set to 40 % switches the plug on, waits for the bridge to report the lamp, then sends on at 40 %",
         %{conn: conn, stub: stub} do
      FakeShelly.serve("fridge")
      {:ok, view, _html} = live(conn, ~p"/lights/#{key(candle())}")
      view |> form("#light_brightness_form", %{"value" => "40"}) |> render_change()
      render_async(view)

      plug_switched_on("fridge")
      assert plug_commands() == [{"fridge", :on, :manual}]

      HueStub.push(stub, [connectivity(candle_connectivity(), "connectivity_issue")])
      :sys.get_state(PowerUp)
      refute_received {:hue_put, _id, _body}

      HueStub.push(stub, [connectivity(candle_connectivity(), "connected")])
      :sys.get_state(PowerUp)
      candle = candle()
      assert_received {:hue_put, ^candle, %{"on" => %{"on" => true}}}

      assert_received {:hue_put, ^candle,
                       %{"on" => %{"on" => true}, "dimming" => %{"brightness" => 40}}}

      HueStub.push(stub, [
        update([%{"id" => candle, "type" => "light", "dimming" => %{"brightness" => 40.0}}])
      ])

      assert PowerUp.starting() == %{}
    end
  end
end
