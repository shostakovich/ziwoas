defmodule ZiwoasWeb.LightLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Lights, Repo}
  alias Ziwoas.Lights.{Light, Snapshot, State}
  alias ZiwoasWeb.LightsComponents

  defp light!(attrs), do: Repo.insert!(struct!(%Light{name: "Lampe"}, attrs))
  defp state!(key, attrs), do: Repo.insert!(struct!(%State{light_key: key}, attrs))

  defp page(conn, key),
    do: conn |> get(~p"/lights/#{key}") |> html_response(200) |> LazyHTML.from_document()

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  test "show renders the detail page for a light by key", %{conn: conn} do
    light!(%{
      key: "ABCDEF01",
      name: "Wohnzimmer Stehlampe",
      supports_color: true,
      supports_color_temp: true
    })

    state!("ABCDEF01", %{on: true, brightness: 60, color_temp_k: 2700})
    doc = page(conn, "ABCDEF01")

    assert doc |> LazyHTML.query("#light_detail h1") |> LazyHTML.text() |> String.trim() ==
             "Wohnzimmer Stehlampe"

    assert count(doc, "#light_detail header a[href='/switches']") == 1

    assert doc |> LazyHTML.query("#app-shell-nav a[aria-current=page]") |> LazyHTML.text() =~
             "Schalten"

    assert count(doc, "#light_detail[data-key=ABCDEF01]") == 1
    assert count(doc, "#light_power button[aria-pressed]") == 2

    assert count(
             doc,
             "form[phx-change=light_command] input#light_brightness[type=range][name=value][value='60']"
           ) == 1

    assert LazyHTML.text(LazyHTML.query(doc, "#light_brightness_form output")) =~ "60 %"
    assert count(doc, "input#light_temp[type=range][name=temp_k][min='2700'][max='6500']") == 1
    assert LazyHTML.text(LazyHTML.query(doc, "#light_panel_white output")) =~ "2.700 K"

    assert doc
           |> LazyHTML.query("#light_panel_switch button[phx-click=show_panel]")
           |> LazyHTML.attribute("phx-value-value") ==
             ~w[white color scenes]

    assert doc |> LazyHTML.query("[data-panel]") |> LazyHTML.attribute("data-panel") ==
             ~w[white color scenes]

    assert doc |> LazyHTML.query("[data-panel][hidden]") |> LazyHTML.attribute("data-panel") ==
             ~w[color scenes]

    assert count(doc, "#light_panel_switch button[phx-value-value=white][aria-pressed=true]") ==
             1
  end

  test "a lamp in colour opens on the colour panel", %{conn: conn} do
    light!(%{key: "C1", supports_color: true})
    state!("C1", %{on: true, brightness: 80, color_r: 255, color_g: 107, color_b: 61})
    doc = page(conn, "C1")

    assert doc |> LazyHTML.query("[data-panel]:not([hidden])") |> LazyHTML.attribute("data-panel") ==
             ["color"]
  end

  test "show 404s for an unknown key", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/lights/NOPE") end
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/lights/NOPE") end
  end

  test "white slider and presets follow the lamp's Kelvin range", %{conn: conn} do
    light!(%{
      key: "ABCDEF09",
      supports_color_temp: true,
      color_temp_min_k: 2200,
      color_temp_max_k: 6500
    })

    state!("ABCDEF09", %{on: true, color_temp_k: 2200})
    doc = page(conn, "ABCDEF09")

    assert count(doc, "input#light_temp[min='2200'][max='6500']") == 1

    assert LazyHTML.text(LazyHTML.query(doc, "#light_presets button[phx-value-value='2200']")) =~
             "Gemütlich"

    assert count(doc, "#light_presets button[aria-pressed=true][phx-value-value='2200']") == 1

    assert doc
           |> LazyHTML.query("#light_panel_white [data-tick]")
           |> Enum.map(&LazyHTML.text/1)
           |> Enum.map(&String.trim/1) ==
             ["3.800 K", "5.400 K"],
           "the presets between the ends are labelled on the scale"
  end

  test "no colour tab without colour support; colour swatches carry their param", %{conn: conn} do
    light!(%{key: "ABCDEF02", supports_color: false, supports_color_temp: true})

    assert count(page(conn, "ABCDEF02"), "#light_panel_switch button[phx-value-value=color]") ==
             0

    light!(%{key: "ABCDEF03", supports_color: true})
    state!("ABCDEF03", %{on: true, brightness: 80, color_r: 255, color_g: 107, color_b: 61})
    doc = page(conn, "ABCDEF03")
    assert count(doc, "fieldset#light_panel_color input[type=radio][data-color^='#']") == 8

    assert doc
           |> LazyHTML.query("fieldset#light_panel_color label.ld-swatch")
           |> Enum.map(&String.trim(LazyHTML.text(&1)))
           |> Enum.take(3) == ["Rot", "Orange", "Gelb"]

    assert count(doc, "label[data-light=wheel] input[type=color][aria-label='Weitere Farbe']") ==
             1
  end

  test "scenes: a button per firmware scene, or a hint", %{conn: conn} do
    light!(%{key: "ABCDEF05", firmware_scenes: ["Forest", "Aurora"]})
    doc = page(conn, "ABCDEF05")

    assert doc
           |> LazyHTML.query("#light_panel_scenes li button")
           |> Enum.map(&String.trim(LazyHTML.text(&1))) == ["Forest", "Aurora"]

    light!(%{key: "ABCDEF06", firmware_scenes: []})

    assert LazyHTML.text(LazyHTML.query(page(conn, "ABCDEF06"), "#light_panel_scenes")) =~
             "Diese Lampe meldet keine Govee-Szenen."
  end

  test "the hero shows the lamp's own plush", %{conn: conn} do
    light!(%{key: "ABCDEF07", sku: "H60A6"})
    assert count(page(conn, "ABCDEF07"), "#light_power img[src*='lamp_ceiling_off']") == 1
  end

  test "a zone lamp has one toggle per zone in the hero, hidden while off", %{conn: conn} do
    light!(%{
      key: "UP1",
      sku: "H60B0",
      zones: ~w[bottomLightToggle sideLightToggle rippleLightToggle]
    })

    doc = page(conn, "UP1")

    assert count(doc, "#light_power #light_zones[role=group] button[id^=zone_]") == 3
    assert count(doc, "#light_zones[hidden]") == 1

    state!("UP1", %{on: true, zone_states: %{"sideLightToggle" => true}})
    doc = page(conn, "UP1")
    assert count(doc, "#light_zones:not([hidden])") == 1
    assert count(doc, "button#zone_sideLightToggle[aria-pressed=true][phx-value-on=false]") == 1
    assert count(doc, "button#zone_bottomLightToggle[aria-pressed=false]") == 1
  end

  test "a simple lamp renders no zone buttons; the gear opens the sheet", %{conn: conn} do
    light!(%{key: "S1", supports_color: true})
    doc = page(conn, "S1")

    assert count(doc, "#light_zones") == 0

    assert count(doc, "button[aria-label=Einstellungen][phx-click=open_settings]") == 1
    assert count(doc, "dialog#light_settings[data-show=false]") == 1
    assert count(doc, "#light_form") == 0
  end

  test "a lamp update re-renders the power hero", %{conn: conn} do
    light!(%{key: "LIVE1", name: "Lampe"})
    state = state!("LIVE1", %{on: false, brightness: 40})
    {:ok, view, _html} = live(conn, ~p"/lights/LIVE1")
    refute has_element?(view, "#light_power button[aria-pressed=true]", "An")
    assert has_element?(view, "input#light_brightness[value='40'][data-on=false]")

    Repo.update!(Ecto.Changeset.change(state, on: true))
    Lights.notify_updated("LIVE1")

    assert has_element?(view, "#light_power button[aria-pressed=true]", "An")
    assert has_element?(view, "input#light_brightness[data-on=true]")
  end

  describe "snapshots" do
    defp snapshot(state), do: %Snapshot{light: %Light{key: "K1", name: "Lampe"}, state: state}

    test "defaults are safe when no state exists" do
      snapshot = snapshot(nil)
      refute Lights.on?(snapshot)
      assert Lights.brightness(snapshot) == 0
      assert Lights.white?(snapshot)
    end

    test "white when a colour temperature is set, else the colour as hex" do
      white = snapshot(%State{on: true, brightness: 60, color_temp_k: 2700})
      assert Lights.white?(white) and LightsComponents.color_hex(white) == nil

      colour = snapshot(%State{on: true, color_r: 255, color_g: 107, color_b: 61})
      refute Lights.white?(colour)
      assert LightsComponents.color_hex(colour) == "#ff6b3d"
      assert Lights.rgb(colour) == {255, 107, 61}
    end

    test "zones come main first with their roles and on bits" do
      light = %Light{zones: ~w[rippleLightToggle bottomLightToggle sideLightToggle]}
      state = %State{zone_states: %{"bottomLightToggle" => true, "rippleLightToggle" => false}}
      zones = Lights.zones(%Snapshot{light: light, state: state})

      assert Enum.map(zones, & &1.key) == ~w[bottomLightToggle rippleLightToggle sideLightToggle]
      assert Enum.map(zones, & &1.role) == [:main, :side, :side]
      assert Enum.map(zones, & &1.on) == [true, false, false]
      assert Lights.zone_lamp?(%Snapshot{light: light, state: nil})
    end

    test "every light by name with its state" do
      light!(%{key: "B", name: "Zweite"})
      light!(%{key: "A", name: "Erste"})
      state!("A", %{on: true, brightness: 70, reachable: true})

      assert [
               %{light: %{name: "Erste"}, state: %{brightness: 70}},
               %{light: %{name: "Zweite"}, state: nil}
             ] =
               Lights.snapshots()
    end
  end
end
