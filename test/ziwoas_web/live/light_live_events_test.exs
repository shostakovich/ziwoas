defmodule ZiwoasWeb.LightLiveEventsTest do
  # The lamp page served by Phoenix: power, zones with the eviction toast and its undo,
  # scenes and the settings sheet as LiveView events.
  use ZiwoasWeb.ConnCase, async: true, db: true

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Mqtt, Ownership, Repo}
  alias Ziwoas.Lights.{Commands, Light, State}

  setup %{repo: repo} do
    Clock.freeze("2026-06-15T17:00:00+02:00")
    Repo.put_writer(:main, repo)
    Ownership.override(%{lights: :phoenix, light_settings: :phoenix})
    on_exit(&Ownership.clear_override/0)
    test = self()

    Mqtt.record(fn _client, topic, payload ->
      send(test, {:published, topic, payload})
      :ok
    end)

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

  test "the power buttons turn the lamp and redraw the hero", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lights/UP1")
    view |> form("#light_power form.flex-grow-1") |> render_submit(%{"on" => "true"})

    assert_received {:published, "govees/UP1/set", ~s({"zone":{"name":"powerSwitch","on":true}})}
    assert Repo.get_by(State, light_key: "UP1").on
    assert has_element?(view, "#light_power button.active[value=true]")
  end

  test "a zone over the limit evicts, toasts, and the undo restores", %{conn: conn} do
    Commands.record_zone_state("UP1", "bottomLightToggle", true)
    Commands.record_zone_state("UP1", "sideLightToggle", true)
    {:ok, view, _html} = live(conn, ~p"/lights/UP1")

    view |> form("#zone_rippleLightToggle") |> render_submit()

    assert view |> element("#light_toast span") |> render() =~
             "Seite ausgeschaltet · max. 2 Zonen"

    assert has_element?(view, "#zone_rippleLightToggle button.active")

    view |> form("#light_toast form") |> render_submit()

    assert Repo.get_by(State, light_key: "UP1").zone_states ==
             %{
               "bottomLightToggle" => true,
               "sideLightToggle" => true,
               "rippleLightToggle" => false
             }

    assert has_element?(view, "#light_toast[hidden]")
  end

  test "the toast hides itself after five seconds, as the toast controller does", %{conn: conn} do
    Commands.record_zone_state("UP1", "bottomLightToggle", true)
    Commands.record_zone_state("UP1", "sideLightToggle", true)
    {:ok, view, _html} = live(conn, ~p"/lights/UP1")
    view |> form("#zone_rippleLightToggle") |> render_submit()

    send(view.pid, :hide_toast)
    assert has_element?(view, "#light_toast[hidden]")
  end

  test "a scene is sent and nothing redraws", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lights/UP1")
    view |> form("#light_panel_scenes form") |> render_submit()
    assert_received {:published, "govees/UP1/set", ~s({"scene":"Lesen"})}
  end

  test "nothing is sent while Phoenix does not own lights", %{conn: conn} do
    Ownership.override(%{lights: :dry_run})
    {:ok, view, _html} = live(conn, ~p"/lights/UP1")
    view |> form("#light_power form.flex-grow-1") |> render_submit(%{"on" => "true"})
    refute_received {:published, _, _}
    refute Repo.get_by(State, light_key: "UP1").on
  end

  test "the settings sheet opens in place, refuses a blank name and saves", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lights/UP1")
    view |> element("a[aria-label=Einstellungen]") |> render_click()

    assert has_element?(
             view,
             "#light_settings dialog[phx-hook=SettingsSheet] form[phx-submit=save_settings]"
           )

    html = view |> form("#light_settings form", %{"light" => %{"name" => ""}}) |> render_submit()
    assert html =~ "Name can&#39;t be blank"
    assert Repo.get_by(Light, key: "UP1").name == "Uplighter"

    view
    |> form("#light_settings form", %{
      "light" => %{"name" => "Stehlampe", "shelly_plug_id" => "fridge"}
    })
    |> render_submit()

    assert %Light{name: "Stehlampe", shelly_plug_id: "fridge"} = Repo.get_by(Light, key: "UP1")
    refute has_element?(view, "#light_settings dialog")
    assert view |> element("h1") |> render() =~ "Stehlampe"
  end

  test "closing the sheet forgets it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lights/UP1")
    view |> element("a[aria-label=Einstellungen]") |> render_click()
    render_hook(view, "close_settings", %{})
    refute has_element?(view, "#light_settings dialog")
  end
end
