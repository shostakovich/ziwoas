defmodule ZiwoasWeb.RoomsLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest
  import Setzkasten.Test.Confirm

  alias Ziwoas.Lights.Light
  alias Ziwoas.{Repo, Rooms}

  defp open_page(conn) do
    {:ok, view, _html} = live(conn, ~p"/switches/rooms")
    view
  end

  defp room!(name) do
    {:ok, room} = Rooms.create(%{"name" => name})
    room
  end

  defp names, do: Enum.map(Rooms.list(), & &1.name)

  defp row_titles(view),
    do:
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#room_list > li")
      |> LazyHTML.attribute("id")

  defp save(view, name),
    do: view |> form("#room_form", room: %{name: name}) |> render_submit()

  test "without rooms it invites to make the first and counts the devices without one", %{
    conn: conn
  } do
    view = open_page(conn)

    assert has_element?(view, "h1", "Räume")
    assert has_element?(view, "#rooms_empty", "Noch keine Räume")
    refute has_element?(view, "#room_list")
    assert has_element?(view, "#rooms_homeless", "1 Gerät noch ohne Raum")
    assert has_element?(view, "#room_form", "Raum anlegen")

    Repo.insert!(%Light{key: "L1", name: "Stehlampe", sku: "H607C"})
    assert has_element?(open_page(conn), "#rooms_homeless", "2 Geräte noch ohne Raum")
  end

  test "Schalten links here", %{conn: conn} do
    {:ok, switches, _html} = live(conn, ~p"/switches")

    {:ok, rooms, _html} =
      switches
      |> element("#sw_rooms_link")
      |> render_click()
      |> follow_redirect(conn, ~p"/switches/rooms")

    assert has_element?(rooms, "#room_form")
  end

  describe "creating" do
    test "adds the room at the end, clears the form and says so", %{conn: conn} do
      room!("Bad")
      view = open_page(conn)

      save(view, "  Küche ")

      assert names() == ["Bad", "Küche"]
      kitchen = Enum.find(Rooms.list(), &(&1.name == "Küche"))
      assert has_element?(view, "#flash-info", "Raum „Küche“ angelegt.")
      assert has_element?(view, "#room-#{kitchen.id}", "Küche")
      assert has_element?(view, "#room-#{kitchen.id}", "0 Geräte")
      refute view |> element("#room_form_name") |> render() =~ "Küche"
      refute has_element?(view, "#rooms_empty")
    end

    test "refuses a blank name as it is typed and on save", %{conn: conn} do
      view = open_page(conn)

      html = view |> form("#room_form", room: %{name: " "}) |> render_change()
      assert html =~ "Gib dem Raum einen Namen"

      html = save(view, "")
      assert html =~ "Gib dem Raum einen Namen"
      assert has_element?(view, "#room_form > #room_form_errors[role=alert]")
      assert has_element?(view, "#room_form[phx-hook='Setzkasten.Components.Forms.FocusInvalid']")
      assert has_element?(view, "#room_form_name[aria-invalid=true]")
      assert names() == []
    end

    test "refuses a name that is taken, and a refused save clears the flash", %{conn: conn} do
      view = open_page(conn)
      save(view, "Bad")
      assert has_element?(view, "#flash-info", "Raum „Bad“ angelegt.")

      html = save(view, "Bad")

      assert html =~ "Diesen Raum gibt es schon"
      refute has_element?(view, "#flash-info")
      assert names() == ["Bad"]
    end
  end

  describe "renaming" do
    test "fills the form, focuses the name and keeps the place", %{conn: conn} do
      office = room!("Büro")
      room!("Bad")
      view = open_page(conn)

      view |> element("#room-#{office.id}-edit") |> render_click()

      assert_push_event(view, "focus_return", %{ids: ["room_form_name"]})
      assert has_element?(view, "#room_form", "„Büro“ umbenennen")
      assert view |> element("#room_form_name") |> render() =~ ~s(value="Büro")

      save(view, "Arbeitszimmer")

      assert names() == ["Arbeitszimmer", "Bad"]
      assert has_element?(view, "#flash-info", "Raum „Arbeitszimmer“ umbenannt.")
      assert has_element?(view, "#room_form", "Raum anlegen")
      refute has_element?(view, "#room_form_cancel")
    end

    test "validates against the room being renamed, refuses another's name", %{conn: conn} do
      office = room!("Büro")
      room!("Bad")
      view = open_page(conn)
      view |> element("#room-#{office.id}-edit") |> render_click()

      html = view |> form("#room_form", room: %{name: ""}) |> render_change()
      assert html =~ "Gib dem Raum einen Namen"

      assert save(view, "Bad") =~ "Diesen Raum gibt es schon"
      assert names() == ["Büro", "Bad"]
      assert has_element?(view, "#room_form", "„Büro“ umbenennen")
    end

    test "Abbrechen goes back to creating", %{conn: conn} do
      office = room!("Büro")
      view = open_page(conn)
      view |> element("#room-#{office.id}-edit") |> render_click()

      view |> element("#room_form_cancel") |> render_click()

      assert has_element?(view, "#room_form", "Raum anlegen")
      save(view, "Bad")
      assert names() == ["Büro", "Bad"]
    end
  end

  describe "moving" do
    test "swaps a room with its neighbour; the ends cannot move further", %{conn: conn} do
      bath = room!("Bad")
      kitchen = room!("Küche")
      office = room!("Büro")
      view = open_page(conn)

      assert has_element?(view, "#room-#{bath.id}-up[disabled]")
      refute has_element?(view, "#room-#{bath.id}-down[disabled]")
      assert has_element?(view, "#room-#{office.id}-down[disabled]")

      view |> element("#room-#{office.id}-up") |> render_click()
      assert names() == ["Bad", "Büro", "Küche"]

      assert row_titles(view) ==
               ["room-#{bath.id}", "room-#{office.id}", "room-#{kitchen.id}"]

      view |> element("#room-#{bath.id}-down") |> render_click()
      assert names() == ["Büro", "Bad", "Küche"]
      assert has_element?(view, "#room-#{office.id}-up[disabled]")

      render_click(view, "move", %{"id" => to_string(office.id), "direction" => "up"})
      render_click(view, "move", %{"id" => "nope", "direction" => "down"})
      assert names() == ["Büro", "Bad", "Küche"]
    end
  end

  describe "deleting" do
    test "asks first, then leaves the room's devices without one", %{conn: conn} do
      bath = room!("Bad")
      kitchen = room!("Küche")
      {:ok, _placed} = Rooms.place_plug("fridge", bath.id)
      view = open_page(conn)

      assert has_element?(view, "#room-#{bath.id}", "1 Gerät")
      refute has_element?(view, "#rooms_homeless")

      assert asked(view, "#room-#{bath.id}-delete").text ==
               "1 Gerät steht danach unter „Ohne Raum“."

      assert asked(view, "#room-#{kitchen.id}-delete").text == nil

      confirm_click(view, "#room-#{bath.id}-delete", "„Bad“ löschen?")

      assert names() == ["Küche"]
      assert Rooms.plug_room("fridge") == nil
      assert has_element?(view, "#flash-info", "Raum „Bad“ gelöscht.")
      refute has_element?(view, "#room-#{bath.id}")
      assert has_element?(view, "#rooms_homeless", "1 Gerät noch ohne Raum")
    end

    test "counts several devices in the question", %{conn: conn} do
      bath = room!("Bad")
      {:ok, _placed} = Rooms.place_plug("fridge", bath.id)
      Repo.insert!(%Light{key: "L1", name: "Spiegel", sku: "H607C", room_id: bath.id})

      assert asked(open_page(conn), "#room-#{bath.id}-delete").text ==
               "2 Geräte stehen danach unter „Ohne Raum“."
    end

    test "deleting the room being renamed goes back to creating", %{conn: conn} do
      bath = room!("Bad")
      view = open_page(conn)
      view |> element("#room-#{bath.id}-edit") |> render_click()

      confirm_click(view, "#room-#{bath.id}-delete", "„Bad“ löschen?")

      assert has_element?(view, "#room_form", "Raum anlegen")
      assert has_element?(view, "#rooms_empty")
    end

    test "a room already gone changes nothing", %{conn: conn} do
      bath = room!("Bad")
      view = open_page(conn)
      Rooms.delete(bath)

      render_click(view, "delete", %{"id" => to_string(bath.id)})
      render_click(view, "edit", %{"id" => to_string(bath.id)})

      refute has_element?(view, "#flash-info")
      refute has_element?(view, "#room-#{bath.id}")
      assert has_element?(view, "#room_form", "Raum anlegen")
    end
  end
end
