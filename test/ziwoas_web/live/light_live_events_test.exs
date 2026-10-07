defmodule ZiwoasWeb.LightLiveEventsTest do
  # The lamp page's controls: power, zones with the eviction toast and its undo,
  # the sliders, swatches and colour wheel, tabs, scenes and the settings sheet. The
  # bridge is FakeGoveeBridge; nothing reaches a lamp.
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{FakeGoveeBridge, Repo, TestClock}
  alias Ziwoas.Lights.{Commands, Light, State}

  setup do
    TestClock.freeze("2026-06-15T17:00:00+02:00")
    bridge!(:ok)

    light =
      Repo.insert!(%Light{
        key: "UP1",
        name: "Uplighter",
        sku: "H60B0",
        zones: ~w[rippleLightToggle sideLightToggle bottomLightToggle],
        firmware_scenes: ["Lesen"]
      })

    Repo.insert!(%State{light_key: "UP1", on: false})
    %{light: light}
  end

  defp bridge!(answer, opts \\ []) do
    if GenServer.whereis(Ziwoas.Govee.Bridge), do: stop_supervised!(FakeGoveeBridge)
    start_supervised!({FakeGoveeBridge, [test: self(), answer: answer] ++ opts})
  end

  defp open_page(conn) do
    {:ok, view, _html} = live(conn, ~p"/lights/UP1")
    view
  end

  defp open_settings(view),
    do: view |> element("button[aria-label=Einstellungen]") |> render_click()

  test "the power buttons turn the lamp and redraw the hero", %{conn: conn} do
    view = open_page(conn)
    view |> element("#light_power button", "An") |> render_click()
    render_async(view)

    assert_received {:govee, "UP1", {:zone, "powerSwitch", true}}
    assert Repo.get_by(State, light_key: "UP1").on
    assert has_element?(view, "#light_power button.active[phx-value-on=true]")
  end

  test "a refused command is a flash and records nothing", %{conn: conn} do
    bridge!({:error, :unknown_lamp})
    view = open_page(conn)
    view |> element("#light_power button", "An") |> render_click()
    render_async(view)

    assert has_element?(view, "#flash-error", "Lampe nicht erreichbar")
    refute Repo.get_by(State, light_key: "UP1").on
  end

  @tag :capture_log
  test "a busy bridge is a flash and the page stays", %{conn: conn} do
    bridge!(:ok, sleep_ms: 1_000)
    view = open_page(conn)
    view |> element("#light_power button", "An") |> render_click()
    refute has_element?(view, "#flash-error")
    render_async(view)
    render_async(view)

    assert has_element?(view, "#flash-error", "Lampe nicht erreichbar")
    refute Repo.get_by(State, light_key: "UP1").on
  end

  test "after a refused slider command both sliders go back to the lamp's values", %{
    conn: conn
  } do
    Repo.update_all(State, set: [brightness: 62, color_temp_k: 2000])
    bridge!({:error, :unknown_lamp})
    view = open_page(conn)

    view |> form("#light_brightness_form", %{"value" => "30"}) |> render_change()
    render_async(view)

    assert has_element?(view, "#flash-error", "Lampe nicht erreichbar")
    assert has_element?(view, "#light_brightness[value='62'][phx-patch-focused]")
    assert has_element?(view, "#light_brightness_form output", "62 %")

    view |> form("#light_panel_white", %{"temp_k" => "6500"}) |> render_change()
    render_async(view)

    assert has_element?(view, "#light_temp[value='2000'][phx-patch-focused]")
    first = view |> element("#light_temp") |> render()

    view |> form("#light_panel_white", %{"temp_k" => "6500"}) |> render_change()
    render_async(view)

    refute view |> element("#light_temp") |> render() == first
  end

  test "after a command the bridge took the sliders leave a focused thumb be", %{conn: conn} do
    view = open_page(conn)
    view |> form("#light_brightness_form", %{"value" => "42"}) |> render_change()
    render_async(view)

    refute has_element?(view, "#light_brightness[phx-patch-focused]")
  end

  test "a zone over the limit evicts, toasts, and the undo restores", %{conn: conn} do
    Commands.record_zone_state("UP1", "bottomLightToggle", true)
    Commands.record_zone_state("UP1", "sideLightToggle", true)
    view = open_page(conn)

    view |> element("#zone_rippleLightToggle") |> render_click()
    render_async(view)

    assert view |> element("#light_toast span") |> render() =~
             "Seite ausgeschaltet · max. 2 Zonen"

    assert has_element?(view, "#light_toast:not([hidden])")
    assert has_element?(view, "#zone_rippleLightToggle.active")
    refute has_element?(view, "#zone_sideLightToggle.active")

    view |> element("#light_toast button", "Rückgängig") |> render_click()
    render_async(view)

    assert Repo.get_by(State, light_key: "UP1").zone_states ==
             %{
               "bottomLightToggle" => true,
               "sideLightToggle" => true,
               "rippleLightToggle" => false
             }

    assert has_element?(view, "#light_toast[hidden]")
  end

  test "the toast hides itself after five seconds", %{conn: conn} do
    Commands.record_zone_state("UP1", "bottomLightToggle", true)
    Commands.record_zone_state("UP1", "sideLightToggle", true)
    view = open_page(conn)
    view |> element("#zone_rippleLightToggle") |> render_click()
    render_async(view)

    send(view.pid, :hide_toast)
    assert has_element?(view, "#light_toast[hidden]")
  end

  test "the brightness slider is a debounced form; the page keeps what it set", %{conn: conn} do
    view = open_page(conn)
    assert has_element?(view, "#light_brightness_form input#light_brightness[phx-debounce]")

    view |> form("#light_brightness_form", %{"value" => "42"}) |> render_change()
    render_async(view)

    assert_received {:govee, "UP1", {:brightness, 42}}
    assert has_element?(view, "#light_brightness_form output", "42 %")
    assert has_element?(view, "#light_brightness[value='42']")
  end

  test "the white slider and the presets send the colour temperature", %{conn: conn} do
    view = open_page(conn)
    assert has_element?(view, "#light_panel_white input#light_temp[phx-debounce]")

    view |> form("#light_panel_white", %{"temp_k" => "4000"}) |> render_change()
    render_async(view)
    assert_received {:govee, "UP1", {:color_temp, 4000}}
    assert has_element?(view, "#light_temp[value='4000']")

    view |> element("#light_panel_white button", "Gemütlich") |> render_click()
    render_async(view)
    assert_received {:govee, "UP1", {:color_temp, 2700}}
    assert has_element?(view, "#light_panel_white button.active[aria-pressed=true]", "Gemütlich")
  end

  test "a swatch and the colour wheel send the colour", %{conn: conn} do
    Repo.update_all(Light, set: [supports_color: true])
    view = open_page(conn)

    view |> element("#light_color_1") |> render_click()
    render_async(view)
    assert_received {:govee, "UP1", {:color, %{r: 255, g: 122, b: 61}}}
    assert has_element?(view, "#light_color_1[checked]")

    view
    |> element("#light_color_wheel[phx-hook=LightDetail]")
    |> render_hook("light_command", %{"command" => "color", "r" => 1, "g" => 2, "b" => 3})

    render_async(view)

    assert_received {:govee, "UP1", {:color, %{r: 1, g: 2, b: 3}}}
    refute has_element?(view, "input[name=light_color][checked]")
    assert has_element?(view, "label.ld-swatch-custom[data-light=wheel][style*='#010203']")
  end

  test "the tabs show one panel at a time", %{conn: conn} do
    Repo.update_all(Light, set: [supports_color: true])
    view = open_page(conn)

    assert has_element?(view, "#light_tab_white[aria-selected=true]")
    assert has_element?(view, "#light_panel_white:not([hidden])")
    assert has_element?(view, "#light_panel_color[hidden]")

    view |> element("#light_tab_color") |> render_click()

    assert has_element?(view, "#light_tab_color.active[aria-selected=true]")
    assert has_element?(view, "#light_panel_color:not([hidden])")
    assert has_element?(view, "#light_panel_white[hidden]")

    render_click(view, "select_tab", %{"tab" => "nope"})
    assert has_element?(view, "#light_panel_color:not([hidden])")
  end

  test "an out of range value or an unknown command sends nothing", %{conn: conn} do
    view = open_page(conn)
    render_hook(view, "light_command", %{"command" => "brightness", "value" => "0"})
    render_hook(view, "light_command", %{"command" => "color", "r" => 256, "g" => 0, "b" => 0})
    render_hook(view, "light_command", %{"command" => "explode"})
    render_hook(view, "light_command", %{})
    render_async(view)

    refute_received {:govee, _, _}
  end

  test "the page commands only its own lamp", %{conn: conn} do
    Repo.insert!(%Light{key: "OTHER", name: "Andere"})
    view = open_page(conn)

    render_hook(view, "light_command", %{
      "light_key" => "OTHER",
      "command" => "brightness",
      "value" => "10"
    })

    render_async(view)

    assert_received {:govee, "UP1", {:brightness, 10}}
  end

  test "a scene is sent and nothing redraws", %{conn: conn} do
    view = open_page(conn)
    view |> element("#light_panel_scenes button", "Lesen") |> render_click()
    render_async(view)
    assert_received {:govee, "UP1", {:scene, "Lesen"}}
  end

  describe "the settings sheet" do
    test "opens in place with the name and a plug dropdown", %{conn: conn} do
      view = open_page(conn)
      open_settings(view)

      assert has_element?(
               view,
               "#light_settings dialog#light_settings_dialog[phx-hook=SettingsSheet] form[phx-submit=save_settings]"
             )

      assert has_element?(view, "#light_settings_dialog button.btn-close[data-dismiss=dialog]")
      assert has_element?(view, "#light_settings_dialog button[data-dismiss=dialog]", "Abbrechen")
      assert view |> element("input[name='light[name]']") |> render() =~ ~s(value="Uplighter")

      options =
        view
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("select[name='light[shelly_plug_id]'] option")
        |> Enum.map(&String.trim(LazyHTML.text(&1)))

      assert options == ["— keine —", "Balkonkraftwerk", "Kühlschrank"]
      refute has_element?(view, "input[name='light[supports_color]']")
    end

    test "refuses a blank name as it is typed and on save", %{conn: conn} do
      view = open_page(conn)
      open_settings(view)

      html = view |> form("#light_form", %{"light" => %{"name" => ""}}) |> render_change()
      assert html =~ "muss ausgefüllt werden"

      html = view |> form("#light_form", %{"light" => %{"name" => ""}}) |> render_submit()
      assert html =~ "muss ausgefüllt werden"
      assert has_element?(view, "#light_settings dialog")
      assert Repo.get_by(Light, key: "UP1").name == "Uplighter"
    end

    test "saves name and plug, closes and says so", %{conn: conn} do
      view = open_page(conn)
      open_settings(view)

      view
      |> form("#light_form", %{"light" => %{"name" => "Stehlampe", "shelly_plug_id" => "fridge"}})
      |> render_submit()

      assert %Light{name: "Stehlampe", shelly_plug_id: "fridge"} = Repo.get_by(Light, key: "UP1")
      refute has_element?(view, "#light_settings dialog")
      assert view |> element("h1") |> render() =~ "Stehlampe"
      assert render(view) =~ "Lampe aktualisiert."
    end

    test "a refused save clears the flash of the one saved before", %{conn: conn} do
      view = open_page(conn)
      open_settings(view)
      view |> form("#light_form", %{"light" => %{"name" => "Stehlampe"}}) |> render_submit()
      assert render(view) =~ "Lampe aktualisiert."

      open_settings(view)
      view |> form("#light_form", %{"light" => %{"name" => ""}}) |> render_submit()

      assert render(view) =~ "muss ausgefüllt werden"
      refute has_element?(view, "#flash-info", "Lampe aktualisiert.")
    end

    test "touches nothing the bridge manages, and no plug is nil", %{conn: conn} do
      Repo.update_all(Light, set: [shelly_plug_id: "fridge"])
      view = open_page(conn)
      open_settings(view)

      render_submit(element(view, "#light_form"), %{
        "light" => %{
          "name" => "Neu",
          "supports_color" => "true",
          "key" => "HACK",
          "shelly_plug_id" => ""
        }
      })

      assert %Light{name: "Neu", supports_color: false, key: "UP1", shelly_plug_id: nil} =
               Repo.get_by(Light, key: "UP1")
    end

    test "closing the sheet forgets it", %{conn: conn} do
      view = open_page(conn)
      open_settings(view)
      view |> element("#light_settings_dialog") |> render_hook("close_settings", %{})
      refute has_element?(view, "#light_settings dialog")
    end
  end
end
