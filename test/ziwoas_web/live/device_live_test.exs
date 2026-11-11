defmodule ZiwoasWeb.DeviceLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Repo, Rooms, TestClock}
  alias Ziwoas.Lights.Light
  alias Ziwoas.Switching
  alias Ziwoas.Switching.Command

  @now "2026-06-15T17:00:00+02:00"

  setup do
    TestClock.freeze(@now)
    :ok
  end

  defp page(conn),
    do: conn |> get(~p"/switches/plugs/fridge") |> html_response(200) |> LazyHTML.from_document()

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp text(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.text() |> plain()

  defp plain(text),
    do: text |> String.replace(["⁠", " "], " ") |> String.split() |> Enum.join(" ")

  defp unix_now, do: Clock.parse!(@now) |> DateTime.to_unix()

  defp open_page(conn) do
    {:ok, view, _html} = live(conn, ~p"/switches/plugs/fridge")
    view
  end

  defp manual_on!(at) do
    Repo.insert!(%Command{
      plug_id: "fridge",
      action: :on,
      source: :manual,
      inserted_at: Clock.parse!(at),
      updated_at: Clock.parse!(at)
    })
  end

  defp options(view),
    do:
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#room_form select[name='place[room_id]'] option")
      |> Enum.map(&String.trim(LazyHTML.text(&1)))

  test "crafted presses for another plug do nothing", %{conn: conn} do
    Ziwoas.FakeShelly.serve("fridge")
    view = open_page(conn)

    for params <- [
          %{"plug_id" => "bkw", "state" => "on"},
          %{"plug_id" => "nope", "state" => "on"}
        ] do
      render_hook(view, "switch_plug", params)
    end

    render_async(view)
    refute_received {:shelly_rpc, _id, _method, _params}
  end

  test "a plug's page follows its power reports", %{conn: conn} do
    state = Repo.insert!(%Ziwoas.Plugs.State{plug_id: "fridge", output: false})
    insert_sample!("fridge", unix_now() - 1, 0.0, 1)
    view = open_page(conn)
    assert has_element?(view, "#device_state [data-headline]", "Aus")

    Repo.update!(Ecto.Changeset.change(state, output: true))
    insert_sample!("fridge", unix_now(), 84.0, 2)
    send(view.pid, {:live, %{}})

    assert has_element?(view, "#device_state [data-headline]", ~r/An\W+84 W/u)
  end

  describe "a plug's page" do
    test "shows the plug's schedule and the two editors' buttons", %{conn: conn} do
      Switching.save_window("fridge", %{
        on_at_time: "18:00",
        off_at_time: "23:00",
        days: [1, 2, 3, 4, 5]
      })

      doc = page(conn)

      assert text(doc, "h1") =~ "Kühlschrank"
      assert text(doc, "#device_schedule h2") == "Schaltzeiten"

      assert text(doc, "#device_schedule li[id^=sw_entry_fridge_]") =~ "Mo–Fr · 18:00–23:00"

      assert doc
             |> LazyHTML.query("#device_schedule button[phx-click=new_entry]")
             |> Enum.map(&String.trim(LazyHTML.text(&1))) ==
               ["Zeitfenster", "Einzelschaltung"]
    end

    test "lists a Zeitfenster as one row and each Einzelschaltung as its own", %{conn: conn} do
      assert count(page(conn), "#device_schedule li[id^=sw_entry_fridge_]") == 0

      Switching.save_window("fridge", %{on_at_time: "18:00", off_at_time: "23:00", days: [1]})

      for at <- ["01:00", "02:00"],
          do: Switching.save_single("fridge", %{at_minute_time: at, action: :off, days: [1]})

      assert count(page(conn), "#device_schedule li[id^=sw_entry_fridge_]") == 3
    end

    test "the status line says since when, where from and what comes next", %{conn: conn} do
      insert_sample!("fridge", unix_now() - 10, 5, 1)
      Switching.save_window("fridge", %{on_at_time: "06:00", off_at_time: "18:00", days: [1]})
      manual_on!("2026-06-14T22:00:00+02:00")

      assert text(page(conn), "#device_state [data-status]") ==
               "An seit gestern 22:00 (manuell) · schaltet um 18:00 aus"
    end

    test "an edge that keeps the state gives way to the one that switches", %{conn: conn} do
      insert_sample!("fridge", unix_now() - 10, 5, 1)
      Switching.save_window("fridge", %{on_at_time: "18:00", off_at_time: "22:00", days: [1]})
      manual_on!("2026-06-15T14:00:00+02:00")

      assert text(page(conn), "#device_state [data-status]") ==
               "An seit 14:00 (manuell) · schaltet um 22:00 aus"
    end

    test "a lit plug heads with its watts, a silent one with „Nicht erreichbar“", %{conn: conn} do
      doc = page(conn)
      assert text(doc, "#device_state [data-headline]") == "Nicht erreichbar"
      assert text(doc, "#device_state [data-status]") == "Noch keine Statusmeldung"
      assert text(doc, "header .badge") == "Offline"
      assert count(doc, "#device_state button.sw-knob[disabled]") == 1

      insert_sample!("fridge", unix_now(), 84.4, 1)
      Repo.insert!(%Ziwoas.Plugs.State{plug_id: "fridge", output: true})
      doc = page(conn)

      assert text(doc, "#device_state [data-headline]") == "An · 84 W"
      assert count(doc, "header .badge") == 0

      assert count(
               doc,
               "#device_state button.sw-knob[aria-pressed=true][phx-value-state=off]"
             ) == 1
    end

    test "names the lamps hanging on the plug, each a link", %{conn: conn} do
      assert count(page(conn), "[data-lamps]") == 0

      Repo.insert!(%Light{key: "L1", name: "Stehlampe", sku: "H607C", shelly_plug_id: "fridge"})
      Repo.insert!(%Light{key: "L2", name: "Uplighter", sku: "H60B0", shelly_plug_id: "fridge"})
      Repo.insert!(%Light{key: "L3", name: "Anderswo", sku: "H60B0"})
      doc = page(conn)

      assert text(doc, "#device_state [data-lamps]") ==
               "Hängt an dieser Steckdose: Stehlampe, Uplighter"

      assert doc
             |> LazyHTML.query("#device_state [data-lamps] a")
             |> LazyHTML.attribute("href") == ["/lights/L1", "/lights/L2"]
    end
  end

  describe "the room select" do
    test "without rooms it says where to make one", %{conn: conn} do
      view = open_page(conn)
      assert options(view) == ["Ohne Raum"]
      assert has_element?(view, "#device_room", "Noch keine Räume")
    end

    test "places the plug, and the blank choice takes it out again", %{conn: conn} do
      {:ok, _bath} = Rooms.create(%{"name" => "Bad"})
      {:ok, kitchen} = Rooms.create(%{"name" => "Küche"})
      view = open_page(conn)

      assert options(view) == ["Ohne Raum", "Bad", "Küche"]
      refute has_element?(view, "#room_form option[selected]")

      view |> form("#room_form", place: %{room_id: kitchen.id}) |> render_change()

      assert Rooms.plug_room("fridge") == kitchen.id
      assert has_element?(view, "#flash-info", "Steht jetzt unter Küche.")
      assert has_element?(view, "#room_form option[value='#{kitchen.id}'][selected]")

      {:ok, switches, _html} = live(conn, ~p"/switches")
      assert has_element?(switches, "#room-#{kitchen.id} #sw_card_fridge")

      view |> form("#room_form", place: %{room_id: ""}) |> render_change()

      assert Rooms.plug_room("fridge") == nil
      assert has_element?(view, "#flash-info", "Ohne Raum gespeichert.")
    end

    test "a room deleted meanwhile is refused and the plug stays where it was", %{conn: conn} do
      {:ok, bath} = Rooms.create(%{"name" => "Bad"})
      view = open_page(conn)
      Rooms.delete(bath)

      render_change(view, "place", %{"place" => %{"room_id" => to_string(bath.id)}})

      assert Rooms.plug_room("fridge") == nil
      assert has_element?(view, "#flash-error", "Diesen Raum gibt es nicht mehr.")
      assert options(view) == ["Ohne Raum"]
    end
  end

  describe "the way back" do
    test "leads to the Schalten view the page was opened from", %{conn: conn} do
      doc =
        conn
        |> get(~p"/switches/plugs/fridge?von=ohne")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert count(doc, "main header a[href='/switches?raum=ohne']") == 1
    end

    test "without a view, or with an unknown one, leads to Schalten", %{conn: conn} do
      assert count(page(conn), "main header a[href='/switches']") == 1

      doc =
        conn
        |> get(~p"/switches/plugs/fridge?von=quatsch")
        |> html_response(200)
        |> LazyHTML.from_document()

      assert count(doc, "main header a[href='/switches']") == 1
    end
  end

  describe "an unknown device" do
    test "is a 404 for a plug that is unknown or does not switch, and a heater unknown", %{
      conn: conn
    } do
      for path <- [~p"/switches/plugs/nope", ~p"/switches/plugs/bkw", ~p"/switches/heaters/nope"] do
        assert_error_sent 404, fn -> get(conn, path) end
        assert_raise ZiwoasWeb.DeviceLive.NotFound, fn -> live(conn, path) end
      end
    end
  end
end
