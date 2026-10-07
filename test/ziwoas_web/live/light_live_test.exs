defmodule ZiwoasWeb.LightLiveTest do
  # Mirrors the show half of test/controllers/lights_controller_test.rb and
  # test/models/light_snapshot_test.rb.
  use ZiwoasWeb.ConnCase, async: true, db: true

  import Phoenix.LiveViewTest

  alias Ziwoas.{Lights, Repo}
  alias Ziwoas.Lights.{Light, Snapshot, State}

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

    assert LazyHTML.text(LazyHTML.query(doc, "h1")) == "Wohnzimmer Stehlampe"
    assert count(doc, "[data-controller=light-detail][data-light-detail-key-value=ABCDEF01]") == 1
    assert count(doc, "#light_power button[aria-pressed]") == 2
    assert count(doc, "input[type=range][data-action='light-detail#brightness']") == 1

    assert count(doc, "input[type=range][data-light-detail-target=temp][min='2700'][max='6500']") ==
             1

    assert count(doc, "button[role=tab][data-light-detail-tab-param=color]") == 1
    assert count(doc, "[role=tabpanel][aria-labelledby=light_tab_white]") == 1
  end

  test "show 404s for an unknown key", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/lights/NOPE") end
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

    assert count(doc, "input[data-light-detail-target=temp][min='2200'][max='6500']") == 1

    assert LazyHTML.text(LazyHTML.query(doc, "button[data-light-detail-temp-param='2200']")) =~
             "Gemütlich"

    assert count(doc, "button.active[aria-pressed=true][data-light-detail-temp-param='2200']") ==
             1
  end

  test "no colour tab without colour support; colour swatches carry their param", %{conn: conn} do
    light!(%{key: "ABCDEF02", supports_color: false, supports_color_temp: true})
    assert count(page(conn, "ABCDEF02"), "button[data-light-detail-tab-param=color]") == 0

    light!(%{key: "ABCDEF03", supports_color: true})
    state!("ABCDEF03", %{on: true, brightness: 80, color_r: 255, color_g: 107, color_b: 61})
    assert count(page(conn, "ABCDEF03"), "input[type=radio][data-light-detail-color-param]") == 8
  end

  test "scenes: a button per firmware scene, or a hint", %{conn: conn} do
    light!(%{key: "ABCDEF05", firmware_scenes: ["Forest", "Aurora"]})
    doc = page(conn, "ABCDEF05")

    assert doc |> LazyHTML.query("form input[name=effect]") |> LazyHTML.attribute("value") == [
             "Forest",
             "Aurora"
           ]

    light!(%{key: "ABCDEF06", firmware_scenes: []})

    assert LazyHTML.text(LazyHTML.query(page(conn, "ABCDEF06"), "[data-tab=scenes] p.mb-0")) ==
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

    assert count(doc, "#light_power [aria-label=Zonen] .row-cols-3 > form[id^=zone_] button") == 3
    assert count(doc, "[aria-label=Zonen][hidden]") == 1
    assert count(doc, "button[role=tab][data-light-detail-tab-param=zones]") == 0

    state!("UP1", %{on: true, zone_states: %{"sideLightToggle" => true}})
    doc = page(conn, "UP1")
    assert count(doc, "[aria-label=Zonen]:not([hidden])") == 1
    assert count(doc, "form#zone_sideLightToggle button.active[aria-pressed=true]") == 1
    assert count(doc, "form#zone_bottomLightToggle button:not(.active)[aria-pressed=false]") == 1
  end

  test "a simple lamp renders no zone buttons; the gear opens the sheet", %{conn: conn} do
    light!(%{key: "S1", supports_color: true})
    doc = page(conn, "S1")

    assert count(doc, "[aria-label=Zonen]") == 0

    assert count(doc, "a[aria-label=Einstellungen][href='/lights/S1/edit'][data-turbo-stream]") ==
             1

    assert count(doc, "#light_settings") == 1
  end

  test "a lamp update re-renders the power hero", %{conn: conn} do
    light!(%{key: "LIVE1", name: "Lampe"})
    state = state!("LIVE1", %{on: false})
    {:ok, view, _html} = live(conn, ~p"/lights/LIVE1")
    refute has_element?(view, "#light_power button.active", "An")

    Repo.update!(Ecto.Changeset.change(state, on: true))
    send(view.pid, {:light_updated, "LIVE1"})

    assert has_element?(view, "#light_power button.active", "An")
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
      assert Lights.white?(white) and Lights.color_hex(white) == nil

      colour = snapshot(%State{on: true, color_r: 255, color_g: 107, color_b: 61})
      refute Lights.white?(colour)
      assert Lights.color_hex(colour) == "#ff6b3d"
      assert Lights.rgb(colour) == {255, 107, 61}
    end

    test "zones come main first with labels and their on bits" do
      light = %Light{zones: ~w[rippleLightToggle bottomLightToggle sideLightToggle]}
      state = %State{zone_states: %{"bottomLightToggle" => true, "rippleLightToggle" => false}}
      zones = Lights.zones(%Snapshot{light: light, state: state})

      assert Enum.map(zones, & &1.key) == ~w[bottomLightToggle rippleLightToggle sideLightToggle]
      assert hd(zones).role == "main" and hd(zones).label == "Leselicht"
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
