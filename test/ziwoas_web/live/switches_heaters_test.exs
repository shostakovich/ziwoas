defmodule ZiwoasWeb.SwitchesHeatersTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest
  import Setzkasten.Test.Confirm

  alias Ziwoas.{FakeFritzBox, Heating, TestClock}
  alias Ziwoas.Fritz.Heaters

  @moduletag :shared_sandbox

  @living "11960 0123456"
  @kitchen "11960 0654321"

  setup do
    TestClock.freeze("2026-11-05T12:00:00+01:00")

    {box, client} =
      FakeFritzBox.start(%{
        @living => %{name: "Wohnzimmer", tsoll: 253, celsius: 205, battery: 80},
        @kitchen => %{name: "Küche", tsoll: 253, celsius: 170, battery: 12, battery_low: true}
      })

    Heating.save_window("119600123456", %{
      on_at_time: "07:00",
      off_at_time: "19:00",
      days: [1, 2, 3, 4, 5]
    })

    pid =
      start_supervised!(
        {Heaters, client: client, zone: "Europe/Berlin", timer: fn _, _, _ -> :ok end}
      )

    send(pid, :poll)
    :sys.get_state(pid)
    %{box: box, pid: pid}
  end

  defp open_page(conn) do
    {:ok, view, _html} = live(conn, ~p"/switches")
    view
  end

  defp text(view, selector),
    do:
      view
      |> element(selector)
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.text()
      |> String.replace(["⁠", " "], " ")
      |> String.split()
      |> Enum.join(" ")

  defp knob(key), do: "#sw_heater_head_#{key} button.sw-knob"

  test "a heater card shows the temperature, the battery and why it heats", %{conn: conn} do
    view = open_page(conn)

    assert text(view, "#sw_heater_119600123456 h3") == "Wohnzimmer"
    assert text(view, "#sw_heater_119600123456 [data-temperature]") == "20,5 °C"
    assert text(view, "#sw_heater_119600123456 [data-battery]") == "Batterie 80 %"
    assert has_element?(view, "#sw_heater_119600123456 [data-battery] svg")
    assert text(view, "#sw_heater_119600123456 [data-status]") == "Heizt auf 21 °C · bis 19:00"
    assert text(view, "#sw_heater_119600123456 [data-heat-c]") == "21,0 °C"
    assert has_element?(view, knob("119600123456") <> "[aria-pressed=true]")
    assert has_element?(view, knob("119600123456") <> " img[src*='heater_on']")
  end

  test "a low battery warns and a heater without windows rests in frost protection", %{
    conn: conn
  } do
    view = open_page(conn)

    assert text(view, "#sw_heater_119600654321 [data-battery]") == "Batterie 12 %"
    assert has_element?(view, "#sw_heater_119600654321 [data-battery] .status-warning")
    assert text(view, "#sw_heater_119600654321 [data-status]") == "Frostschutz"
    assert text(view, "#sw_heater_119600654321 [data-temperature]") == "17,0 °C"
    assert has_element?(view, knob("119600654321") <> "[aria-pressed=false]")
    assert has_element?(view, knob("119600654321") <> " img[src*='heater_off']")
  end

  test "the heaters come after the lamps and before the plugs", %{conn: conn} do
    html = conn |> get(~p"/switches") |> html_response(200)
    [before_plugs, _] = String.split(html, ~s(id="sw_plugs"), parts: 2)
    assert before_plugs =~ ~s(id="sw_heaters")
  end

  test "the knob heats by hand until four hours later", %{conn: conn} do
    view = open_page(conn)

    view |> element(knob("119600654321")) |> render_click()
    render_async(view)

    assert_received {:sethkrtsoll, @kitchen, "42"}

    assert text(view, "#sw_heater_119600654321 [data-status]") ==
             "Heizt auf 21 °C · manuell bis 16:00"

    assert has_element?(view, knob("119600654321") <> "[aria-pressed=true]")
  end

  test "pressing the knob while heating switches to frost protection", %{conn: conn} do
    view = open_page(conn)

    view |> element(knob("119600123456")) |> render_click()
    render_async(view)

    assert_received {:sethkrtsoll, @living, "253"}

    assert text(view, "#sw_heater_119600123456 [data-status]") ==
             "Frostschutz · heizt ab Fr 07:00"
  end

  test "a temperature set on the thermostat shows as set, the stepper keeps the Heiztemperatur",
       %{conn: conn, box: box, pid: pid} do
    view = open_page(conn)
    TestClock.freeze("2026-11-05T14:01:00+01:00")
    FakeFritzBox.turn(box, @kitchen, 46)
    send(pid, :poll)
    :sys.get_state(pid)

    assert text(view, "#sw_heater_119600654321 [data-status]") ==
             "Heizt auf 23 °C · manuell bis 18:01"

    assert text(view, "#sw_heater_119600654321 [data-heat-c]") == "21,0 °C"
    refute_received {:sethkrtsoll, @kitchen, "42"}
  end

  test "a press the box refuses shows a flash and leaves the knob", %{conn: conn, box: box} do
    view = open_page(conn)
    FakeFritzBox.set(box, :refuse, true)

    view |> element(knob("119600654321")) |> render_click()
    html = render_async(view)

    assert html =~ "Küche: Schalten fehlgeschlagen — Heizung nicht erreichbar"
    assert has_element?(view, knob("119600654321") <> "[aria-pressed=false]")
  end

  test "− and + stop at 19 and 22 °C", %{conn: conn} do
    Heating.put_heat_c!(Heating.get_heater("119600654321"), 19.0)
    Heating.put_heat_c!(Heating.get_heater("119600123456"), 22.0)
    view = open_page(conn)

    assert has_element?(view, "#sw_heat_down_119600654321[disabled]")
    refute has_element?(view, "#sw_heat_up_119600654321[disabled]")
    assert has_element?(view, "#sw_heat_up_119600123456[disabled]")
    refute has_element?(view, "#sw_heat_down_119600123456[disabled]")
  end

  test "a warmer Heiztemperatur applies at once while heating", %{conn: conn} do
    view = open_page(conn)

    view |> element("#sw_heat_up_119600123456") |> render_click()
    render_async(view)

    assert_received {:sethkrtsoll, @living, "43"}
    assert text(view, "#sw_heater_119600123456 [data-heat-c]") == "21,5 °C"
    assert text(view, "#sw_heater_119600123456 [data-status]") == "Heizt auf 21,5 °C · bis 19:00"
  end

  test "a heater the box no longer reaches is offline with a disabled knob", %{
    conn: conn,
    box: box,
    pid: pid
  } do
    view = open_page(conn)
    FakeFritzBox.set(box, :down, true)

    ExUnit.CaptureLog.capture_log(fn ->
      send(pid, :poll)
      :sys.get_state(pid)
    end)

    assert text(view, "#sw_heater_head_119600123456 .badge") == "Offline"
    assert has_element?(view, knob("119600123456") <> "[disabled]")
    assert has_element?(view, "#sw_heat_down_119600123456[disabled]")
    assert has_element?(view, "#sw_heat_up_119600123456[disabled]")
    refute has_element?(view, "#sw_heater_119600123456 [data-temperature]")
    refute has_element?(view, "#sw_heater_119600123456 [data-battery]")
  end

  test "a colder Heiztemperatur applies at once while heating", %{conn: conn} do
    view = open_page(conn)

    view |> element("#sw_heat_down_119600123456") |> render_click()
    render_async(view)

    assert_received {:sethkrtsoll, @living, "41"}
    assert text(view, "#sw_heater_119600123456 [data-heat-c]") == "20,5 °C"
  end

  test "a Heiztemperatur the box refuses is kept and says so", %{conn: conn, box: box} do
    view = open_page(conn)
    FakeFritzBox.set(box, :refuse, true)

    view |> element("#sw_heat_up_119600123456") |> render_click()
    html = render_async(view)

    assert html =~ "Wohnzimmer: Heiztemperatur nicht geändert — Heizung nicht erreichbar"
    assert text(view, "#sw_heater_119600123456 [data-heat-c]") == "21,0 °C"
    assert Heating.get_heater("119600123456").heat_c == 21.0
  end

  test "crafted events do nothing", %{conn: conn} do
    assert_received {:sethkrtsoll, @living, "42"}
    Heating.put_heat_c!(Heating.get_heater("119600123456"), 22.0)
    view = open_page(conn)

    for {event, params} <- [
          {"heat_c", %{"heater_key" => "119600123456", "step" => "up"}},
          {"heat_c", %{"heater_key" => "nope", "step" => "down"}},
          {"heat_c", %{"heater_key" => "119600123456", "step" => "sideways"}},
          {"switch_heater", %{"heater_key" => "nope", "state" => "heat"}},
          {"switch_heater", %{"heater_key" => "119600123456", "state" => "toggle"}},
          {"new_entry", %{"heater_key" => "119600123456", "kind" => "rule"}},
          {"edit_entry", %{"heater_key" => "119600123456", "kind" => "window", "id" => %{}}},
          {"set_enabled", %{"heater_key" => "119600123456", "kind" => "window", "id" => ["1"]}},
          {"delete_entry", %{"heater_key" => "nope", "kind" => "window", "id" => "1"}}
        ] do
      html = render_hook(view, event, params)
      render_async(view)
      refute html =~ "fehlgeschlagen"
      refute html =~ "nicht geändert"
    end

    refute_received {:sethkrtsoll, _, _}
    assert Heating.get_heater("119600123456").heat_c == 22.0
    assert length(Heating.windows("119600123456")) == 1
    refute has_element?(view, "#sw_119600123456_new_form")
  end

  test "a window form with a broken payload is refused, not crashed", %{conn: conn} do
    view = open_page(conn)
    view |> element("#sw_new_window_119600654321") |> render_click()

    render_hook(view, "validate_entry", %{"heater_key" => "119600654321", "window" => "x"})
    render_hook(view, "save_entry", %{"heater_key" => "119600654321", "window" => "x"})

    assert has_element?(view, "#sw_119600654321_new_form")
    assert Heating.windows("119600654321") == []
  end

  test "a thermostat turned to its maximum heats at Maximum", %{conn: conn, box: box, pid: pid} do
    view = open_page(conn)
    FakeFritzBox.turn(box, @kitchen, 254)
    send(pid, :poll)
    :sys.get_state(pid)

    assert text(view, "#sw_heater_119600654321 [data-status]") ==
             "Heizt auf Maximum · manuell bis 16:00"
  end

  test "the knob shows what the thermostat was last set to, the status line what is due",
       %{conn: conn, box: box, pid: pid} do
    view = open_page(conn)
    FakeFritzBox.set(box, :refuse, true)

    ExUnit.CaptureLog.capture_log(fn ->
      Heating.save_window("119600654321", %{on_at_time: "07:00", off_at_time: "19:00", days: [4]})
      :sys.get_state(pid)
    end)

    send(view.pid, {:heaters, Heating.readings()})

    assert text(view, "#sw_heater_119600654321 [data-status]") == "Heizt auf 21 °C · bis 19:00"
    assert has_element?(view, knob("119600654321") <> "[aria-pressed=false]")
    assert has_element?(view, knob("119600654321") <> "[phx-value-state=heat]")
  end

  describe "Zeitfenster" do
    test "the disclosure counts the windows and offers only windows", %{conn: conn} do
      view = open_page(conn)

      assert text(view, "#sw_heater_schedule_119600123456 > summary") == "Zeitfenster 1"

      assert text(view, "#sw_rules_119600123456 li[id^=sw_entry_] p.font-medium") ==
               "Mo–Fr · 07:00–19:00"

      assert has_element?(view, "#sw_new_window_119600123456")
      refute has_element?(view, "#sw_new_rule_119600123456")
      assert text(view, "#sw_heater_schedule_119600654321 > summary") == "Zeitfenster"
    end

    test "a new window is saved with the plugs' editor", %{conn: conn} do
      view = open_page(conn)
      view |> element("#sw_new_window_119600654321") |> render_click()

      view
      |> form("#sw_119600654321_new_form",
        window: %{on_at_time: "06:30", off_at_time: "07:30", days: ["5"]}
      )
      |> render_submit()

      assert render(view) =~ "Zeitfenster gespeichert."

      assert text(view, "#sw_rules_119600654321 li[id^=sw_entry_] p.font-medium") ==
               "Fr · 06:30–07:30"

      assert text(view, "#sw_heater_119600654321 [data-status]") ==
               "Frostschutz · heizt ab Fr 06:30"
    end

    test "a refused window keeps the editor open with the plugs' messages", %{conn: conn} do
      view = open_page(conn)
      view |> element("#sw_new_window_119600654321") |> render_click()

      html =
        view
        |> form("#sw_119600654321_new_form",
          window: %{on_at_time: "07:00", off_at_time: "07:00", days: ["5"]}
        )
        |> render_submit()

      assert html =~ "An- und Aus-Zeit müssen sich unterscheiden"
      assert Heating.windows("119600654321") == []
    end

    test "a window can be paused, edited and deleted", %{conn: conn} do
      [window] = Heating.windows("119600123456")
      row = "#sw_entry_119600123456_#{window.id}"
      view = open_page(conn)

      view |> element("#{row}_toggle") |> render_click()
      refute hd(Heating.windows("119600123456")).enabled
      assert text(view, "#sw_heater_119600123456 [data-status]") == "Frostschutz"

      view |> element("#{row}_edit") |> render_click()

      view
      |> form("#sw_119600123456_#{window.id}_form", window: %{on_at_time: "08:00"})
      |> render_submit()

      assert hd(Heating.windows("119600123456")).on_minute == 480

      confirm_click(view, "#{row}_delete", "Zeitfenster löschen?")
      assert Heating.windows("119600123456") == []
    end
  end

  test "without heaters there is no section", %{conn: conn} do
    stop_supervised!(Heaters)
    Ziwoas.Repo.delete_all(Ziwoas.Heating.Heater)

    refute conn |> get(~p"/switches") |> html_response(200) =~ "Heizungen"
  end
end
