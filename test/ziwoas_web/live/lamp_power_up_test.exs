defmodule ZiwoasWeb.LampPowerUpTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ziwoas.LampPower

  alias Ziwoas.{FakeGoveeBridge, FakeShelly, Repo, TestClock}
  alias Ziwoas.Lights.{Light, State}
  alias Ziwoas.Plugs

  @start "2026-06-15T17:00:00+02:00"

  setup do
    TestClock.freeze(@start)
    start_supervised!({FakeGoveeBridge, test: self()})
    start_power_up!()
    Repo.insert!(%Light{key: "FL1", name: "Stehlampe", sku: "H607C", shelly_plug_id: "fridge"})
    Repo.insert!(%State{light_key: "FL1", on: true})
    Repo.insert!(%Plugs.State{plug_id: "fridge", output: false})
    :ok
  end

  defp card_text(view),
    do: view |> element("#light_card_FL1 .card-body") |> render() |> LazyHTML.from_fragment()

  defp summary(view),
    do: view |> card_text() |> LazyHTML.query(".text-body-secondary") |> Enum.map(&text/1)

  defp text(node), do: node |> LazyHTML.text() |> String.trim()

  defp tap_lamp(view) do
    view |> element("#light_card_FL1 button.sw-lamp-knob") |> render_click()
    render_async(view)
  end

  defp later(seconds), do: later(@start, seconds)
  defp hear(telemetry), do: hear("FL1", telemetry)
  defp plug_switched_on, do: plug_switched_on("fridge")

  defp relay!(output) do
    Repo.update_all(Plugs.State, set: [output: output])
    Plugs.notify_live([%{id: "fridge", output: output}])
  end

  defp sent do
    receive do
      {:govee, key, verb} -> [{key, verb} | sent()]
    after
      0 -> []
    end
  end

  test "a lamp whose plug is off shows as off and unpowered", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/switches")

    assert ["Aus · stromlos" | _] = summary(view)
    assert has_element?(view, "#light_card_FL1 button.sw-lamp-knob.off[phx-value-on=true]")
  end

  test "tapping an unpowered lamp switches its plug on, counts while it starts, and switches it once it answers",
       %{conn: conn} do
    FakeShelly.serve("fridge")
    {:ok, view, _html} = live(conn, ~p"/switches")
    tap_lamp(view)

    plug_switched_on()
    assert plug_commands() == [{"fridge", :on, :manual}]
    assert_received {:govee_watch, "FL1"}
    refute_received {:govee, "FL1", _verb}
    assert ["Startet … 0 s", "Steckdose an, warte auf Lampe"] = summary(view)

    later(18)
    await(fn -> match?(["Startet … 18 s" | _], summary(view)) end)

    hear(nil)
    assert sent() == [{"FL1", {:power, true}}]

    relay!(true)
    hear(%{on: true})
    assert_received {:govee_unwatch, "FL1"}

    assert ["An · Weiß" | _] = summary(view)
  end

  test "a lamp that does not answer within 60 s gives up and leaves the plug on",
       %{conn: conn} do
    FakeShelly.serve("fridge")
    {:ok, view, _html} = live(conn, ~p"/switches")
    tap_lamp(view)
    plug_switched_on()

    later(61)
    tick("FL1")
    assert_received {:govee_unwatch, "FL1"}

    assert has_element?(
             view,
             "#flash-error",
             "Stehlampe nach 60 s nicht erreichbar — Steckdose bleibt an."
           )

    hear(nil)
    assert sent() == []
    refute_receive {:shelly_rpc, "fridge", "Switch.Set", %{on: false}}, 100
    assert plug_commands() == [{"fridge", :on, :manual}]
  end

  test "a plug that does not answer is a flash and nothing starts", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/switches")
    tap_lamp(view)

    assert_receive {:govee_unwatch, "FL1"}
    assert has_element?(view, "#flash-error", "Stehlampe: Steckdose nicht erreichbar")
    assert ["Aus · stromlos" | _] = summary(view)
  end

  test "the detail page says when the lamp gave up", %{conn: conn} do
    FakeShelly.serve("fridge")
    {:ok, view, _html} = live(conn, ~p"/lights/FL1")
    view |> element("#light_power button", "An") |> render_click()
    render_async(view)
    plug_switched_on()

    later(60)
    tick("FL1")
    assert_received {:govee_unwatch, "FL1"}

    assert has_element?(
             view,
             "#flash-error",
             "Stehlampe nach 60 s nicht erreichbar — Steckdose bleibt an."
           )

    refute has_element?(view, "#light_starting")
  end

  test "switching an unpowered lamp off switches no plug", %{conn: conn} do
    FakeShelly.serve("fridge")
    {:ok, view, _html} = live(conn, ~p"/lights/FL1")
    view |> element("#light_power button", "Aus") |> render_click()
    render_async(view)

    refute_receive {:shelly_rpc, _plug, _method, _params}, 100
    assert sent() == []
    refute Repo.get_by(State, light_key: "FL1").on
    assert has_element?(view, "#light_power", "Aus · stromlos")
  end

  test "commands while the lamp starts are collected, the last one per kind wins",
       %{conn: conn} do
    FakeShelly.serve("fridge")
    {:ok, view, _html} = live(conn, ~p"/lights/FL1")
    view |> element("#light_power button", "An") |> render_click()
    render_async(view)

    assert has_element?(
             view,
             "#light_starting.alert",
             "Lampe startet — Einstellungen werden übernommen, sobald sie erreichbar ist."
           )

    for value <- ~w[40 60] do
      view |> form("#light_brightness_form", %{"value" => value}) |> render_change()
      render_async(view)
    end

    plug_switched_on()
    hear(nil)
    assert sent() == [{"FL1", {:power, true}}, {"FL1", {:brightness, 60}}]
  end

  test "switching off while the lamp starts sends only off and leaves the plug on",
       %{conn: conn} do
    FakeShelly.serve("fridge")
    {:ok, view, _html} = live(conn, ~p"/lights/FL1")
    view |> element("#light_power button", "An") |> render_click()
    render_async(view)
    view |> form("#light_brightness_form", %{"value" => "60"}) |> render_change()
    render_async(view)
    view |> element("#light_power button", "Aus") |> render_click()
    render_async(view)

    plug_switched_on()
    hear(nil)
    assert sent() == [{"FL1", {:power, false}}]
    refute_receive {:shelly_rpc, "fridge", "Switch.Set", %{on: false}}, 100
  end

  test "a tap on a starting lamp turns it off, and the card shows the wish", %{conn: conn} do
    FakeShelly.serve("fridge")
    {:ok, view, _html} = live(conn, ~p"/switches")
    tap_lamp(view)
    assert has_element?(view, "#light_card_FL1 button.sw-lamp-knob:not(.off)[phx-value-on=false]")

    tap_lamp(view)
    assert has_element?(view, "#light_card_FL1 button.sw-lamp-knob.off[phx-value-on=true]")
    plug_switched_on()
  end

  test "the detail page follows its plug's relay", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lights/FL1")
    assert has_element?(view, "#light_power", "Aus · stromlos")

    relay!(true)
    refute has_element?(view, "#light_power", "Aus · stromlos")

    relay!(false)
    assert has_element?(view, "#light_power", "Aus · stromlos")
  end

  test "leaving the page aborts nothing, not even the plug switching on", %{conn: conn} do
    FakeShelly.serve("fridge")
    {:ok, view, _html} = live(conn, ~p"/switches")
    tap_lamp(view)
    assert_received {:govee_watch, "FL1"}

    GenServer.stop(view.pid)
    plug_switched_on()
    assert plug_commands() == [{"fridge", :on, :manual}]

    hear(nil)
    assert sent() == [{"FL1", {:power, true}}]
  end
end
