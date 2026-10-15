defmodule ZiwoasWeb.SwitchesLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Repo, TestClock, TestConfigs}
  alias Ziwoas.Lights.{Light, State}
  alias Ziwoas.Plugs
  alias Ziwoas.Switching
  alias Ziwoas.Switching.Rule

  @now "2026-06-15T17:00:00+02:00"

  setup do
    TestClock.freeze(@now)

    light = Repo.insert!(%Light{key: "ABCDEF01", name: "Wohnzimmer Stehlampe", sku: "H607C"})
    Repo.insert!(%State{light_key: light.key, on: true, brightness: 60, color_temp_k: 2700})
    %{light: light}
  end

  defp page(conn),
    do: conn |> get(~p"/switches") |> html_response(200) |> LazyHTML.from_document()

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp text(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.text() |> plain()

  defp plain(text),
    do: text |> String.replace(["\u2060", "\u00A0"], " ") |> String.split() |> Enum.join(" ")

  defp unix_now, do: Clock.parse!(@now) |> DateTime.to_unix()

  defp state!(output),
    do: Repo.insert!(%Plugs.State{plug_id: "fridge", output: output})

  test "lamp tile links to the detail page and exposes a toggle knob", %{conn: conn} do
    doc = page(conn)

    assert text(doc, "#light_card_ABCDEF01 a[href='/lights/ABCDEF01']") ==
             "Wohnzimmer Stehlampe"

    assert count(
             doc,
             "#light_card_ABCDEF01 button[aria-label='Wohnzimmer Stehlampe'][aria-pressed=true]"
           ) == 1

    assert text(doc, "#light_card_ABCDEF01 [data-status]") == "An · Weiß"
    assert text(doc, "#light_card_ABCDEF01 [data-brightness]") == "60 %"
    assert count(doc, "#light_card_ABCDEF01 button img[src*='lamp_floorlamp_on']") == 1

    assert count(
             doc,
             "button[phx-click=light_command][phx-value-light_key=ABCDEF01][phx-value-command=turn][phx-value-on=false]"
           ) == 1
  end

  test "lists only switchable plugs", %{conn: conn} do
    body = conn |> get(~p"/switches") |> html_response(200)
    assert body =~ "Kühlschrank"
    refute body =~ "Balkonkraftwerk"
  end

  test "shows the plug's schedule and the two editors' links", %{conn: conn} do
    Switching.save_window("fridge", %{
      on_at_time: "18:00",
      off_at_time: "23:00",
      days: [1, 2, 3, 4, 5]
    })

    doc = page(conn)

    assert text(doc, "#sw_card_fridge li[id^=sw_entry_fridge_]") =~ "Mo–Fr · 18:00–23:00"

    assert doc
           |> LazyHTML.query("#sw_card_fridge button[phx-click=new_entry]")
           |> Enum.map(&String.trim(LazyHTML.text(&1))) ==
             ["Zeitfenster", "Einzelschaltung"]
  end

  test "the summary counts Schaltzeiten, not rows; without any it is bare", %{conn: conn} do
    doc = page(conn)
    assert text(doc, "#sw_schedule_fridge > summary") == "Schaltzeiten"
    assert count(doc, "#sw_schedule_fridge > summary > span") == 0

    Switching.save_window("fridge", %{on_at_time: "18:00", off_at_time: "23:00", days: [1]})

    for at <- ["01:00", "02:00"],
        do: Switching.save_single("fridge", %{at_minute_time: at, action: :off, days: [1]})

    assert text(page(conn), "#sw_schedule_fridge > summary > span") == "4"
  end

  test "rules of a plug that left ziwoas.yml stay out of sight, not deleted", %{conn: conn} do
    Repo.insert!(%Rule{plug_id: "gone", action: :off, at_minute: 60, days: [1]})
    refute conn |> get(~p"/switches") |> html_response(200) =~ "gone"
    assert Repo.aggregate(Rule, :count) == 1
  end

  test "a plug that reports power shows its watts under a lit knob", %{conn: conn} do
    insert_sample!("fridge", unix_now(), 84.4, 1)
    state!(true)
    doc = page(conn)

    assert count(
             doc,
             "#sw_head_fridge button[aria-label='Kühlschrank'][aria-pressed=true][phx-value-state=off] img[src*='switch_plush_on']"
           ) == 1

    assert text(doc, "#sw_head_fridge [data-watt]") == "84 W"
    refute text(doc, "#sw_head_fridge") =~ "Offline"
  end

  test "the watt chip groups thousands the German way", %{conn: conn} do
    insert_sample!("fridge", unix_now(), 1980.2, 1)
    state!(true)
    assert text(page(conn), "#sw_head_fridge [data-watt]") == "1.980 W"
  end

  test "a silent plug is marked offline, its knob disabled and without watts", %{conn: conn} do
    doc = page(conn)
    assert text(doc, "#sw_head_fridge .badge") == "Offline"

    assert count(
             doc,
             "#sw_head_fridge button[aria-pressed=false][disabled] img[src*='switch_plush_off']"
           ) == 1

    assert count(doc, "#sw_head_fridge [data-watt]") == 0
    assert text(doc, "#sw_head_fridge [data-status]") == "Noch keine Statusmeldung"
  end

  test "the status line says since when, where from and what comes next", %{conn: conn} do
    insert_sample!("fridge", unix_now() - 10, 5, 1)
    Switching.save_window("fridge", %{on_at_time: "06:00", off_at_time: "18:00", days: [1]})

    Repo.insert!(%Ziwoas.Switching.Command{
      plug_id: "fridge",
      action: :on,
      source: :manual,
      inserted_at: Clock.parse!("2026-06-14T22:00:00+02:00"),
      updated_at: Clock.parse!("2026-06-14T22:00:00+02:00")
    })

    assert text(page(conn), "#sw_head_fridge [data-status]") ==
             "An seit gestern 22:00 (manuell) · schaltet um 18:00 aus"
  end

  test "an edge that keeps the state gives way to the one that switches", %{conn: conn} do
    insert_sample!("fridge", unix_now() - 10, 5, 1)
    Switching.save_window("fridge", %{on_at_time: "18:00", off_at_time: "22:00", days: [1]})

    Repo.insert!(%Ziwoas.Switching.Command{
      plug_id: "fridge",
      action: :on,
      source: :manual,
      inserted_at: Clock.parse!("2026-06-15T14:00:00+02:00"),
      updated_at: Clock.parse!("2026-06-15T14:00:00+02:00")
    })

    assert text(page(conn), "#sw_head_fridge [data-status]") ==
             "An seit 14:00 (manuell) · schaltet um 22:00 aus"
  end

  test "a plug update rebuilds the plug heads", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/switches")
    refute render(view) =~ "84 W"

    insert_sample!("fridge", unix_now(), 84.4, 1)
    state!(true)
    Ziwoas.Plugs.notify_live([])

    assert render(view) =~ "84 W"
  end

  test "a lamp update re-renders the lamp tiles", %{conn: conn, light: light} do
    {:ok, view, _html} = live(conn, ~p"/switches")
    assert has_element?(view, "#light_card_#{light.key} [data-status]", ~r/An\W+Weiß/u)

    Repo.update_all(State, set: [on: false])
    Ziwoas.Lights.notify_updated(light.key)

    assert has_element?(view, "#light_card_#{light.key} [data-status]", "Aus")
  end

  test "a lamp tile navigates to the lamp's page inside the live session", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/switches")

    assert has_element?(
             view,
             "#light_card_ABCDEF01 a[data-phx-link=redirect][href='/lights/ABCDEF01']"
           )

    {:ok, lamp, _html} =
      view
      |> element("#light_card_ABCDEF01 a")
      |> render_click()
      |> follow_redirect(conn, ~p"/lights/ABCDEF01")

    assert has_element?(lamp, "h1", "Wohnzimmer Stehlampe")
    assert has_element?(lamp, "header a[data-phx-link=redirect][href='/switches']")
  end

  test "without switchable plugs the plug section says how to get one", %{conn: conn} do
    TestConfigs.put(TestConfigs.plugs())
    doc = page(conn)

    assert text(doc, "#sw_plugs") =~ "Keine schaltbaren Steckdosen"
    assert text(doc, "#sw_plugs") =~ "switchable: true"
    assert count(doc, "#sw_plugs article") == 0
    assert count(doc, "#sw_lamps article") == 1
  end
end
