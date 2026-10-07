defmodule ZiwoasWeb.SolakonLiveConfigTest do
  use ZiwoasWeb.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Repo, Solakon, TestClock}
  alias Ziwoas.Solakon.{Control, Reading}

  @now "2026-10-05T12:00:00+02:00"

  setup do
    Ziwoas.TestConfigs.put(Ziwoas.TestConfigs.load(:inverter))
    TestClock.freeze(@now)
  end

  defp page(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()
  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  defp reading!(seconds_ago) do
    Repo.insert!(%Reading{
      taken_at: @now |> Clock.parse!() |> DateTime.add(-seconds_ago),
      active_power_w: 260.0,
      pv_power_w: 310.0,
      battery_power_w: 50.0,
      battery_soc_pct: 84
    })
  end

  test "the auto-regulation follows an enabled config and the stored state", %{conn: conn} do
    doc = page(conn, "/solakon")
    assert texts(doc, ".stat-value#solakon-control-state") == ["Aktiv"]
    assert texts(doc, "#solakon-control-help") == ["folgt dem gemessenen Verbrauch"]
    assert count(doc, "button#solakon-control-toggle[aria-checked=true]") == 1
    assert count(doc, "button#solakon-control-toggle[disabled]") == 0

    Repo.insert!(%Control.State{paused: true})
    doc = page(conn, "/solakon")
    assert texts(doc, ".stat-value#solakon-control-state") == ["Pausiert"]
    assert count(doc, "button#solakon-control-toggle[aria-checked=false]") == 1
  end

  test "the Auto-Regelung switch pauses and resumes the stored control", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/solakon")

    view |> element("#solakon-control-toggle") |> render_click()
    render_async(view)

    assert has_element?(view, "#solakon-control-state", "Pausiert")
    assert has_element?(view, "#solakon-control-help", "pausiert")
    assert has_element?(view, "button#solakon-control-toggle[aria-checked=false]:not([disabled])")
    refute Solakon.control_active?()

    view |> element("#solakon-control-toggle") |> render_click()
    render_async(view)

    assert has_element?(view, "#solakon-control-state", "Aktiv")
    assert has_element?(view, "#solakon-control-help", "folgt dem gemessenen Verbrauch")
    assert has_element?(view, "button#solakon-control-toggle[aria-checked=true]")
    assert Solakon.control_active?()
  end

  test "an outlet switch the inverter does not take keeps the switch and names the failure", %{
    conn: conn
  } do
    reading!(30)
    {:ok, view, _html} = live(conn, ~p"/solakon")
    assert has_element?(view, "button#solakon-eps-toggle[aria-checked=false]")

    log =
      capture_log(fn ->
        view |> element("#solakon-eps-toggle") |> render_click()
        render_async(view)
      end)

    assert log =~ "EPS switch failed"
    assert has_element?(view, "#solakon-eps-error:not([hidden])", "Schalten fehlgeschlagen")
    assert has_element?(view, "button#solakon-eps-toggle[aria-checked=false]:not([disabled])")
    assert has_element?(view, "#solakon-eps-state", "Aus")
  end

  test "a fresh reading shows the battery in the hero and splits the energy flow", %{conn: conn} do
    insert_sample!("fridge", (@now |> Clock.parse!() |> DateTime.to_unix()) - 5, 200.0, 1.0)
    reading!(30)

    doc = page(conn, "/")

    assert count(doc, "#dashboard_hero .col[hidden]") == 0
    assert texts(doc, "#dashboard_hero .display-4") == ["310", "84"]
    assert count(doc, "#dashboard_hero img[alt='Batterie'][src*='solakon_battery_charging']") == 1
    assert texts(doc, "#tile_netbalance_now .stat-value") == ["+60 W"]

    [state] =
      doc
      |> LazyHTML.query("#energy_flow[phx-hook=EnergyFlow]")
      |> LazyHTML.attribute("data-state")

    assert %{"solakon_online" => true, "flows" => %{"solar_to_battery_w" => 50.0}} =
             JSON.decode!(state)
  end

  test "a stale reading leaves the inverter offline", %{conn: conn} do
    reading!(121)

    assert count(page(conn, "/"), "#dashboard_hero .col[hidden]") == 1
  end
end
