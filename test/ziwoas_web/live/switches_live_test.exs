defmodule ZiwoasWeb.SwitchesLiveTest do
  # Mirrors test/controllers/switches_controller_test.rb and the lamp tile's component test.
  use ZiwoasWeb.ConnCase, async: true, db: true

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Ownership, Repo}
  alias Ziwoas.Lights.{Light, State}
  alias Ziwoas.Plugs
  alias Ziwoas.Switching.{Rule, Rules}

  @now "2026-06-15T17:00:00+02:00"

  setup %{repo: repo} do
    Clock.freeze(@now)
    Repo.put_writer(:main, repo)
    Ownership.override(%{switch_schedule: :phoenix})
    on_exit(&Ownership.clear_override/0)

    light = Repo.insert!(%Light{key: "ABCDEF01", name: "Wohnzimmer Stehlampe", sku: "H607C"})
    Repo.insert!(%State{light_key: light.key, on: true, brightness: 60, color_temp_k: 2700})
    %{light: light}
  end

  defp page(conn),
    do: conn |> get(~p"/switches") |> html_response(200) |> LazyHTML.from_document()

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp text(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()

  defp unix_now, do: Clock.parse!(@now) |> DateTime.to_unix()

  defp state!(output),
    do: Repo.insert!(%Plugs.State{plug_id: "fridge", output: output})

  test "lamp tile links to the detail page and exposes a toggle knob", %{conn: conn} do
    doc = page(conn)

    assert count(
             doc,
             "#light_card_ABCDEF01 a[aria-label='Wohnzimmer Stehlampe Details'][href='/lights/ABCDEF01']"
           ) == 1

    assert count(doc, ".card[data-light-key=ABCDEF01] button.sw-knob") == 1
    assert text(doc, "#light_card_ABCDEF01 .small.text-body-secondary") == "An · Weiß"
    assert text(doc, "#light_card_ABCDEF01 span.badge") == "60 %"
    assert count(doc, "button.sw-lamp-knob img.sw-knob-plush[src*='lamp_floorlamp_']") == 1
    assert count(doc, "form[action='/lights/ABCDEF01/command'] input[name=on][value=false]") == 1
  end

  test "lists only switchable plugs", %{conn: conn} do
    body = conn |> get(~p"/switches") |> html_response(200)
    assert body =~ "Kühlschrank"
    refute body =~ "Balkonkraftwerk"
  end

  test "shows the plug's schedule and the two editors' links", %{conn: conn} do
    Rules.save_window("fridge", %{
      on_at_time: "18:00",
      off_at_time: "23:00",
      days: [1, 2, 3, 4, 5]
    })

    doc = page(conn)

    assert LazyHTML.text(LazyHTML.query(doc, "#sw_card_fridge .badge.rounded-pill")) =~
             "Mo–Fr · 18:00–23:00"

    assert doc
           |> LazyHTML.query("#sw_card_fridge a[data-turbo-stream]")
           |> Enum.map(&String.trim(LazyHTML.text(&1))) ==
             ["", "+ Zeitfenster", "+ Einzelschaltung"]
  end

  test "the summary counts Schaltzeiten, not rows; without any it is bare", %{conn: conn} do
    assert text(page(conn), "#sw_card_fridge summary") == "Schaltzeiten"

    Rules.save_window("fridge", %{on_at_time: "18:00", off_at_time: "23:00", days: [1]})

    for at <- ["01:00", "02:00"],
        do: Rules.save_single("fridge", %{at_minute_time: at, action: "off", days: [1]})

    assert text(page(conn), "#sw_card_fridge summary") == "Schaltzeiten (4)"
  end

  test "rules of a plug that left ziwoas.yml stay out of sight, not deleted", %{conn: conn} do
    Repo.insert!(%Rule{plug_id: "gone", action: "off", at_minute: 60, days: [1]})
    refute conn |> get(~p"/switches") |> html_response(200) =~ "gone"
    assert Repo.aggregate(Rule, :count) == 1
  end

  test "a plug that reports power shows its watts under a lit knob", %{conn: conn} do
    insert_sample!("fridge", unix_now(), 84.4, 1)
    state!(true)
    doc = page(conn)

    assert count(
             doc,
             "#sw_head_fridge button.btn.btn-light.btn-icon.sw-knob:not(.off)[aria-label='Kühlschrank ausschalten'] img[src*='switch_plush_on']"
           ) == 1

    assert text(doc, "#sw_head_fridge .badge") =~ "84 W"
    assert count(doc, "#sw_card_fridge.opacity-75") == 0
  end

  test "the watt chip groups thousands the German way", %{conn: conn} do
    insert_sample!("fridge", unix_now(), 1980.2, 1)
    state!(true)
    assert text(page(conn), "#sw_head_fridge .badge") == "⚡1.980 W"
  end

  test "a silent plug is dimmed, its knob disabled and without watts", %{conn: conn} do
    doc = page(conn)
    assert count(doc, "#sw_card_fridge.card.opacity-75") == 1

    assert count(doc, "#sw_head_fridge button.sw-knob.off[disabled] img[src*='switch_plush_off']") ==
             1

    assert count(doc, "#sw_head_fridge .badge") == 0
    assert text(doc, "#sw_head_fridge .small.text-body-secondary") == "Noch keine Statusmeldung"
  end

  test "the status line says since when, where from and what comes next", %{conn: conn} do
    insert_sample!("fridge", unix_now() - 10, 5, 1)
    Rules.save_window("fridge", %{on_at_time: "18:00", off_at_time: "23:00", days: [1]})

    Repo.insert!(%Ziwoas.Switching.Command{
      plug_id: "fridge",
      action: "on",
      source: "schedule",
      created_at: Clock.parse!("2026-06-15T06:00:00+02:00"),
      updated_at: Clock.parse!("2026-06-15T06:00:00+02:00")
    })

    assert text(page(conn), "#sw_head_fridge .small.text-body-secondary") ==
             "An seit 06:00 (Zeitplan) · nächste Schaltung: 18:00 → an"
  end

  test "a dashboard beat rebuilds the plug heads", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/switches")
    refute render(view) =~ "84 W"

    insert_sample!("fridge", unix_now(), 84.4, 1)
    state!(true)
    send(view.pid, {:dashboard_live, []})

    assert render(view) =~ "84 W"
  end

  test "a lamp update re-renders the lamp tiles", %{conn: conn, light: light} do
    {:ok, view, _html} = live(conn, ~p"/switches")
    assert has_element?(view, "#light_card_#{light.key} .small", "An · Weiß")

    Repo.update_all(State, set: [on: false])
    send(view.pid, {:light_updated, light.key})

    assert has_element?(view, "#light_card_#{light.key} .small", "Aus")
  end
end
