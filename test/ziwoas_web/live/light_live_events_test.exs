defmodule ZiwoasWeb.LightLiveEventsTest do
  # The lamp page's controls: power, zones with the eviction toast and its undo,
  # scenes, the LightDetail hook's sliders and the settings sheet. The broker is
  # TestMqtt; nothing reaches a lamp.
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.Lights.{Commands, Light, State}
  alias Ziwoas.{Repo, TestClock, TestMqtt}

  setup do
    TestClock.freeze("2026-06-15T17:00:00+02:00")
    record(:ok)

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

  defp record(answer) do
    test = self()

    TestMqtt.record(fn _client, topic, payload ->
      send(test, {:published, topic, payload})
      answer
    end)
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

    assert_received {:published, "govees/UP1/set", ~s({"zone":{"name":"powerSwitch","on":true}})}
    assert Repo.get_by(State, light_key: "UP1").on
    assert has_element?(view, "#light_power button.active[phx-value-on=true]")
  end

  test "a broker failure is a flash and records nothing", %{conn: conn} do
    record({:error, :closed})
    view = open_page(conn)
    view |> element("#light_power button", "An") |> render_click()

    assert render(view) =~ "Lampe nicht erreichbar — MQTT-Broker nicht erreichbar"
    refute Repo.get_by(State, light_key: "UP1").on
  end

  test "a zone over the limit evicts, toasts, and the undo restores", %{conn: conn} do
    Commands.record_zone_state("UP1", "bottomLightToggle", true)
    Commands.record_zone_state("UP1", "sideLightToggle", true)
    view = open_page(conn)

    view |> element("#zone_rippleLightToggle") |> render_click()

    assert view |> element("#light_toast span") |> render() =~
             "Seite ausgeschaltet · max. 2 Zonen"

    assert has_element?(view, "#light_toast:not([hidden])")
    assert has_element?(view, "#zone_rippleLightToggle.active")
    refute has_element?(view, "#zone_sideLightToggle.active")

    view |> element("#light_toast button", "Rückgängig") |> render_click()

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

    send(view.pid, :hide_toast)
    assert has_element?(view, "#light_toast[hidden]")
  end

  test "the LightDetail hook's brightness, white and colour are sent as commands", %{
    conn: conn
  } do
    view = open_page(conn)
    hook = element(view, "#light_detail[phx-hook=LightDetail][data-key=UP1]")

    render_hook(hook, "light_command", %{"command" => "brightness", "value" => "42"})
    render_hook(hook, "light_command", %{"command" => "color_temp", "temp_k" => "4000"})
    render_hook(hook, "light_command", %{"command" => "color", "r" => 255, "g" => 122, "b" => 61})

    assert_received {:published, "govees/UP1/set", ~s({"brightness":42})}
    assert_received {:published, "govees/UP1/set", ~s({"color_temp_k":4000})}
    assert_received {:published, "govees/UP1/set", ~s({"color":{"b":61,"g":122,"r":255}})}
  end

  test "an out of range value or an unknown command sends nothing", %{conn: conn} do
    view = open_page(conn)
    render_hook(view, "light_command", %{"command" => "brightness", "value" => "0"})
    render_hook(view, "light_command", %{"command" => "color", "r" => 256, "g" => 0, "b" => 0})
    render_hook(view, "light_command", %{"command" => "explode"})
    render_hook(view, "light_command", %{})

    refute_received {:published, _, _}
  end

  test "the page commands only its own lamp", %{conn: conn} do
    Repo.insert!(%Light{key: "OTHER", name: "Andere"})
    view = open_page(conn)

    render_hook(view, "light_command", %{
      "light_key" => "OTHER",
      "command" => "brightness",
      "value" => "10"
    })

    assert_received {:published, "govees/UP1/set", ~s({"brightness":10})}
  end

  test "a scene is sent and nothing redraws", %{conn: conn} do
    view = open_page(conn)
    view |> element("#light_panel_scenes button", "Lesen") |> render_click()
    assert_received {:published, "govees/UP1/set", ~s({"scene":"Lesen"})}
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
