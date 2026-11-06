defmodule ZiwoasWeb.SwitchesHeatersTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest
  import Setzkasten.Test.Confirm

  alias Ziwoas.{FakeFritzBox, Heating, Rooms, TestClock}
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

  defp open_device(conn, key) do
    {:ok, view, _html} = live(conn, ~p"/switches/heaters/#{key}")
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

  defp knob(key), do: "#sw_heater_#{key} button.sw-knob"

  test "a heater tile shows the temperature and why it heats, a good battery only on its page",
       %{conn: conn} do
    view = open_page(conn)

    assert text(view, "#sw_heater_119600123456 h3") == "Wohnzimmer"

    assert has_element?(
             view,
             "#sw_heater_119600123456 h3 a[href='/switches/heaters/119600123456']"
           )

    assert text(view, "#sw_heater_119600123456 [data-temperature]") == "20,5 °C"
    refute has_element?(view, "#sw_heater_119600123456 [data-battery]")
    assert text(view, "#sw_heater_119600123456 [data-status]") == "Heizt auf 21 °C · bis 19:00"
    assert text(view, "#sw_heater_119600123456 [data-heat-c]") == "21,0 °C"
    assert has_element?(view, knob("119600123456") <> "[aria-pressed=true]")
    assert has_element?(view, knob("119600123456") <> " img[src*='heater_on']")
    assert text(view, "#sw_summary_heizungen [data-summary]") == "1 heizt"

    device = open_device(conn, "119600123456")

    assert text(device, "h1") =~ "Wohnzimmer"
    assert text(device, "#device_state [data-temperature]") == "20,5 °C"
    assert text(device, "#device_state [data-battery]") == "Batterie 80 %"
    assert has_element?(device, "#device_state [data-battery] svg")
    assert text(device, "#device_state [data-status]") == "Heizt auf 21 °C · bis 19:00"
    assert text(device, "#device_state [data-heat-c]") == "21,0 °C"
    assert has_element?(device, "#device_state button.sw-knob[aria-pressed=true]")
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

  test "the heaters come before the plugs in their room, by name", %{conn: conn} do
    ids =
      conn
      |> get(~p"/switches")
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("#room-none article")
      |> LazyHTML.attribute("id")

    assert ids == ["sw_heater_119600654321", "sw_heater_119600123456", "sw_card_fridge"]
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

    assert text(view, "#sw_heater_119600123456 .badge") == "Offline"
    assert has_element?(view, knob("119600123456") <> "[disabled]")
    assert has_element?(view, "#sw_heat_down_119600123456[disabled]")
    assert has_element?(view, "#sw_heat_up_119600123456[disabled]")
    refute has_element?(view, "#sw_heater_119600123456 [data-temperature]")
    refute has_element?(view, "#sw_heater_119600123456 [data-battery]")

    device = open_device(conn, "119600123456")
    assert text(device, "header .badge") == "Offline"
    assert text(device, "#device_state [data-status]") == "Nicht erreichbar"
    assert has_element?(device, "#device_state button.sw-knob[disabled]")
    assert has_element?(device, "#sw_heat_up_119600123456[disabled]")
    refute has_element?(device, "#device_state [data-temperature]")
    refute has_element?(device, "#device_state [data-battery]")
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

  test "crafted events do nothing on Schalten", %{conn: conn} do
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

  test "crafted events do nothing on a heater's page", %{conn: conn} do
    assert_received {:sethkrtsoll, @living, "42"}
    Heating.put_heat_c!(Heating.get_heater("119600123456"), 22.0)
    view = open_device(conn, "119600123456")

    for {event, params} <- [
          {"heat_c", %{"heater_key" => "119600123456", "step" => "up"}},
          {"heat_c", %{"heater_key" => "119600123456", "step" => "sideways"}},
          {"switch_heater", %{"heater_key" => "119600123456", "state" => "toggle"}},
          {"switch_plug", %{"plug_id" => "fridge", "state" => "on"}},
          {"switch_heater", %{"heater_key" => "119600654321", "state" => "heat"}},
          {"heat_c", %{"heater_key" => "119600654321", "step" => "down"}},
          {"new_entry", %{"heater_key" => "119600123456", "kind" => "rule"}},
          {"new_entry", %{"heater_key" => "119600654321", "kind" => "window"}},
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
    refute_received {:shelly_rpc, _, _, _}
    assert Heating.get_heater("119600123456").heat_c == 22.0
    assert length(Heating.windows("119600123456")) == 1
    refute has_element?(view, "form[phx-submit=save_entry]")
  end

  test "a heater the box stops listing sends its page back to Schalten", %{conn: conn} do
    view = open_device(conn, "119600123456")
    send(view.pid, {:heaters, %{}})

    assert %{"error" => "Diese Heizung gibt es nicht mehr."} = assert_redirect(view, "/switches")
  end

  test "a window form with a broken payload is refused, not crashed", %{conn: conn} do
    view = open_device(conn, "119600654321")
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
    test "a heater's page lists its windows and offers only windows", %{conn: conn} do
      view = open_device(conn, "119600123456")

      assert text(view, "#device_schedule h2") == "Zeitfenster"

      assert text(view, "#device_schedule #sw_rules_119600123456 li[id^=sw_entry_] p.font-medium") ==
               "Mo–Fr · 07:00–19:00"

      assert has_element?(view, "#sw_new_window_119600123456")
      refute has_element?(view, "#sw_new_rule_119600123456")

      kitchen = open_device(conn, "119600654321")
      refute has_element?(kitchen, "#sw_rules_119600654321 li[id^=sw_entry_]")
      assert has_element?(kitchen, "#sw_new_window_119600654321")
    end

    test "a new window is saved with the plugs' editor", %{conn: conn} do
      view = open_device(conn, "119600654321")
      view |> element("#sw_new_window_119600654321") |> render_click()

      view
      |> form("#sw_119600654321_new_form",
        window: %{on_at_time: "06:30", off_at_time: "07:30", days: ["5"]}
      )
      |> render_submit()

      assert render(view) =~ "Zeitfenster gespeichert."

      assert text(view, "#sw_rules_119600654321 li[id^=sw_entry_] p.font-medium") ==
               "Fr · 06:30–07:30"

      assert text(view, "#device_state [data-status]") == "Frostschutz · heizt ab Fr 06:30"
    end

    test "a refused window keeps the editor open with the plugs' messages", %{conn: conn} do
      view = open_device(conn, "119600654321")
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
      view = open_device(conn, "119600123456")

      view |> element("#{row}_toggle") |> render_click()
      refute hd(Heating.windows("119600123456")).enabled
      assert text(view, "#device_state [data-status]") == "Frostschutz"

      view |> element("#{row}_edit") |> render_click()

      view
      |> form("#sw_119600123456_#{window.id}_form", window: %{on_at_time: "08:00"})
      |> render_submit()

      assert hd(Heating.windows("119600123456")).on_minute == 480

      confirm_click(view, "#{row}_delete", "Zeitfenster löschen?")
      assert Heating.windows("119600123456") == []
    end
  end

  describe "a heater's page" do
    test "its knob heats by hand and the stepper sets the Heiztemperatur", %{conn: conn} do
      view = open_device(conn, "119600654321")
      assert text(view, "#device_state [data-status]") == "Frostschutz"

      view |> element("#device_state button.sw-knob") |> render_click()
      render_async(view)

      assert_received {:sethkrtsoll, @kitchen, "42"}
      assert text(view, "#device_state [data-status]") == "Heizt auf 21 °C · manuell bis 16:00"
      assert has_element?(view, "#device_state button.sw-knob[aria-pressed=true]")

      view |> element("#sw_heat_up_119600654321") |> render_click()
      render_async(view)

      assert_received {:sethkrtsoll, @kitchen, "43"}
      assert text(view, "#device_state [data-heat-c]") == "21,5 °C"
    end

    test "a press the box refuses is a flash", %{conn: conn, box: box} do
      view = open_device(conn, "119600654321")
      FakeFritzBox.set(box, :refuse, true)

      view |> element("#device_state button.sw-knob") |> render_click()
      render_async(view)

      assert has_element?(
               view,
               "#flash-error",
               "Schalten fehlgeschlagen — Heizung nicht erreichbar"
             )
    end

    test "the room select places the heater and takes it out again", %{conn: conn} do
      {:ok, bath} = Rooms.create(%{"name" => "Bad"})
      view = open_device(conn, "119600654321")

      options =
        view
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("#room_form select[name='place[room_id]'] option")
        |> Enum.map(&String.trim(LazyHTML.text(&1)))

      assert options == ["Ohne Raum", "Bad"]

      view |> form("#room_form", place: %{room_id: bath.id}) |> render_change()

      assert Heating.get_heater("119600654321").room_id == bath.id
      assert has_element?(view, "#flash-info", "Steht jetzt unter Bad.")
      assert has_element?(view, "#room_form option[value='#{bath.id}'][selected]")

      {:ok, switches, _html} = live(conn, ~p"/switches")
      assert has_element?(switches, "#room-#{bath.id} #sw_heater_119600654321")

      view |> form("#room_form", place: %{room_id: ""}) |> render_change()

      assert Heating.get_heater("119600654321").room_id == nil
      assert has_element?(view, "#flash-info", "Ohne Raum gespeichert.")
    end

    test "a room deleted meanwhile is refused", %{conn: conn} do
      {:ok, bath} = Rooms.create(%{"name" => "Bad"})
      view = open_device(conn, "119600654321")
      Rooms.delete(bath)

      render_change(view, "place", %{"place" => %{"room_id" => to_string(bath.id)}})

      assert Heating.get_heater("119600654321").room_id == nil
      assert has_element?(view, "#flash-error", "Diesen Raum gibt es nicht mehr.")
    end
  end

  test "without heaters there is no section", %{conn: conn} do
    stop_supervised!(Heaters)
    Ziwoas.Repo.delete_all(Ziwoas.Heating.Heater)

    refute conn |> get(~p"/switches") |> html_response(200) =~ "Heizungen"
  end
end
