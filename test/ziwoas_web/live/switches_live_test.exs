defmodule ZiwoasWeb.SwitchesLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{
    Clock,
    FakeGoveeBridge,
    FakeShelly,
    Repo,
    Residents,
    Rooms,
    Sensors,
    TestClock,
    TestConfigs
  }

  alias Ziwoas.Heating.Heater
  alias Ziwoas.Lights.{Light, State}
  alias Ziwoas.Plugs
  alias Ziwoas.Sensors.Reading
  alias Ziwoas.Switching
  alias Ziwoas.Switching.Rule

  @now "2026-06-15T17:00:00+02:00"

  setup do
    TestClock.freeze(@now)

    light = Repo.insert!(%Light{key: "ABCDEF01", name: "Wohnzimmer Stehlampe", sku: "H607C"})
    Repo.insert!(%State{light_key: light.key, on: true, brightness: 60, color_temp_k: 2700})
    %{light: light}
  end

  defp page(conn, path \\ ~p"/switches"),
    do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp text(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.text() |> plain()

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&plain(LazyHTML.text(&1)))

  defp ids(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute("id")

  defp hrefs(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute("href")

  defp plain(text),
    do: text |> String.replace(["⁠", " "], " ") |> String.split() |> Enum.join(" ")

  defp unix_now, do: Clock.parse!(@now) |> DateTime.to_unix()

  defp state!(output),
    do: Repo.insert!(%Plugs.State{plug_id: "fridge", output: output})

  defp room!(name) do
    {:ok, room} = Rooms.create(%{"name" => name})
    room
  end

  defp lamp!(key, name, on, room \\ nil) do
    light = Repo.insert!(%Light{key: key, name: name, sku: "H607C", room_id: room && room.id})
    Repo.insert!(%State{light_key: key, on: on, brightness: 50})
    light
  end

  defp heater!(key, name, room \\ nil),
    do: Repo.insert!(%Heater{key: key, ain: key, name: name, room_id: room && room.id})

  defp reading!(attrs) do
    taken_at = @now |> Clock.parse!() |> DateTime.add(-5 * 60, :second)
    Repo.insert!(struct!(%Reading{device_id: "TEST_INDOOR", taken_at: taken_at}, attrs))
  end

  test "lamp tile links to the detail page and exposes a toggle knob", %{conn: conn} do
    doc = page(conn)

    assert text(doc, "#light_card_ABCDEF01 a[href='/lights/ABCDEF01?von=alle']") ==
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

  test "a plug tile links to the plug's page, which holds the schedule", %{conn: conn} do
    Switching.save_window("fridge", %{
      on_at_time: "18:00",
      off_at_time: "23:00",
      days: [1, 2, 3, 4, 5]
    })

    doc = page(conn)

    assert text(doc, "#sw_card_fridge a[href='/switches/plugs/fridge?von=alle']") == "Kühlschrank"
    assert count(doc, "li[id^=sw_entry_fridge_]") == 0
    assert count(doc, "button[phx-click=new_entry]") == 0
  end

  test "rules of a plug that left ziwoas.yml stay out of sight, not deleted", %{conn: conn} do
    Repo.insert!(%Rule{plug_id: "gone", action: :off, at_minute: 60, days: [1]})
    refute conn |> get(~p"/switches") |> html_response(200) =~ "gone"
    assert Repo.aggregate(Rule, :count) == 1
  end

  test "a plug that reports power shows its watts beside a lit knob", %{conn: conn} do
    insert_sample!("fridge", unix_now(), 84.4, 1)
    state!(true)
    doc = page(conn)

    assert count(
             doc,
             "#sw_card_fridge button[aria-label='Kühlschrank'][aria-pressed=true][phx-value-state=off] img[src*='switch_plush_on']"
           ) == 1

    assert text(doc, "#sw_card_fridge [data-watt]") == "84 W"
    refute text(doc, "#sw_card_fridge") =~ "Offline"
  end

  test "the watt chip groups thousands the German way", %{conn: conn} do
    insert_sample!("fridge", unix_now(), 1980.2, 1)
    state!(true)
    assert text(page(conn), "#sw_card_fridge [data-watt]") == "1.980 W"
  end

  test "a silent plug is marked offline, its knob disabled and without watts", %{conn: conn} do
    doc = page(conn)
    assert text(doc, "#sw_card_fridge .badge") == "Offline"

    assert count(
             doc,
             "#sw_card_fridge button[aria-pressed=false][disabled] img[src*='switch_plush_off']"
           ) == 1

    assert count(doc, "#sw_card_fridge [data-watt]") == 0
    assert text(doc, "#sw_card_fridge [data-status]") == "Noch keine Statusmeldung"
  end

  test "a plug tile's status is short: the state and what comes next", %{conn: conn} do
    insert_sample!("fridge", unix_now() - 10, 5, 1)
    assert text(page(conn), "#sw_card_fridge [data-status]") == "Aus"

    Switching.save_window("fridge", %{on_at_time: "06:00", off_at_time: "18:00", days: [1]})

    Repo.insert!(%Ziwoas.Switching.Command{
      plug_id: "fridge",
      action: :on,
      source: :manual,
      inserted_at: Clock.parse!("2026-06-14T22:00:00+02:00"),
      updated_at: Clock.parse!("2026-06-14T22:00:00+02:00")
    })

    assert text(page(conn), "#sw_card_fridge [data-status]") == "An · schaltet um 18:00 aus"
  end

  test "a plug update rebuilds the plug tiles", %{conn: conn} do
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
             "#light_card_ABCDEF01 a[data-phx-link=redirect][href='/lights/ABCDEF01?von=alle']"
           )

    {:ok, lamp, _html} =
      view
      |> element("#light_card_ABCDEF01 a")
      |> render_click()
      |> follow_redirect(conn, ~p"/lights/ABCDEF01?von=alle")

    assert has_element?(lamp, "h1", "Wohnzimmer Stehlampe")
    assert has_element?(lamp, "header a[data-phx-link=redirect][href='/switches?raum=alle']")
  end

  test "without switchable plugs there is no plug tile and no Steckdosen summary", %{conn: conn} do
    TestConfigs.put(TestConfigs.plugs())
    doc = page(conn)

    assert count(doc, "article[data-plug-id]") == 0
    assert count(doc, "#sw_summary_steckdosen") == 0
    assert count(doc, "#light_card_ABCDEF01") == 1
  end

  test "with nothing to switch the page says how to get a plug", %{conn: conn} do
    TestConfigs.put(TestConfigs.plugs())
    Repo.delete_all(State)
    Repo.delete_all(Light)
    doc = page(conn)

    assert text(doc, "main") =~ "Noch nichts zu schalten"
    assert text(doc, "main") =~ "switchable: true"
    assert count(doc, "#sw_summary") == 0
    assert count(doc, "section.sw-room") == 0
  end

  describe "rooms" do
    test "without rooms everything stands under „Ohne Raum“", %{conn: conn} do
      doc = page(conn)

      assert ids(doc, "section.sw-room") == ["room-none"]
      assert text(doc, "#room-none_heading") =~ "Ohne Raum"
      assert text(doc, "#room-none") =~ "Neu erkannte Geräte landen hier"
      assert texts(doc, "#sw_rooms_nav a") == ["Alle", "Ohne Raum"]
      assert ids(doc, "#room-none article") == ["light_card_ABCDEF01", "sw_card_fridge"]
    end

    test "groups devices by room in the rooms' order, empty rooms left out", %{
      conn: conn,
      light: light
    } do
      bath = room!("Bad")
      living = room!("Wohnzimmer")
      _empty = room!("Keller")

      Repo.update_all(Light, set: [room_id: living.id])
      heater!("h1", "Badheizung", bath)
      {:ok, _placed} = Rooms.place_plug("fridge", bath.id)
      lamp!("LAMP2", "Leselampe", false)
      Rooms.move(living, :up)

      doc = page(conn)

      assert ids(doc, "section.sw-room") == ["room-#{living.id}", "room-#{bath.id}", "room-none"]
      assert texts(doc, "#sw_rooms_nav a") == ["Alle", "Wohnzimmer", "Bad", "Ohne Raum"]

      assert hrefs(doc, "#sw_rooms_nav a") == [
               "/switches?raum=alle",
               "/switches?raum=#{living.id}",
               "/switches?raum=#{bath.id}",
               "/switches?raum=ohne"
             ]

      assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=alle"]

      assert ids(doc, "#room-#{living.id} article") == ["light_card_#{light.key}"]
      assert ids(doc, "#room-#{bath.id} article") == ["sw_heater_h1", "sw_card_fridge"]
      assert ids(doc, "#room-none article") == ["light_card_LAMP2"]
      refute text(doc, "#room-#{bath.id}") =~ "Neu erkannte Geräte"
    end

    test "with every device in a room there is no „Ohne Raum“", %{conn: conn} do
      room = room!("Küche")
      Repo.update_all(Light, set: [room_id: room.id])
      {:ok, _placed} = Rooms.place_plug("fridge", room.id)

      doc = page(conn)
      assert ids(doc, "section.sw-room") == ["room-#{room.id}"]
      assert texts(doc, "#sw_rooms_nav a") == ["Alle", "Küche"]
    end

    test "within a room heaters come first, then lamps, then plugs", %{conn: conn} do
      room = room!("Wohnzimmer")
      Repo.update_all(Light, set: [room_id: room.id])
      heater!("h1", "Heizung", room)
      {:ok, _placed} = Rooms.place_plug("fridge", room.id)

      assert ids(page(conn), "#room-#{room.id} article") ==
               ["sw_heater_h1", "light_card_ABCDEF01", "sw_card_fridge"]
    end

    test "a room's heading counts what is on, or says everything is off", %{conn: conn} do
      room = room!("Wohnzimmer")
      Repo.update_all(Light, set: [room_id: room.id])
      lamp!("LAMP2", "Leselampe", true, room)
      lamp!("LAMP3", "Nachtlicht", false, room)
      insert_sample!("fridge", unix_now(), 84.4, 1)
      state!(true)
      {:ok, _placed} = Rooms.place_plug("fridge", room.id)

      doc = page(conn)
      assert text(doc, "#room-#{room.id}_heading [data-on-count]") == "3 an"
      assert count(doc, "#sw_rooms_nav a[data-view='#{room.id}'] .sw-room-dot-on") == 1

      Repo.update_all(State, set: [on: false])
      Repo.update_all(Plugs.State, set: [output: false])
      doc = page(conn)

      assert text(doc, "#room-#{room.id}_heading [data-on-count]") == "alles aus"
      assert count(doc, "#sw_rooms_nav .sw-room-dot-on") == 0
      assert count(doc, "#room-#{room.id}_lamps_off") == 0
    end
  end

  describe "the view" do
    setup %{light: light} do
      living = room!("Wohnzimmer")
      bath = room!("Bad")
      Repo.update_all(Light, set: [room_id: living.id])
      heater!("h1", "Badheizung", bath)
      lamp!("NONE", "Flur", false)
      %{living: living, bath: bath, light: light}
    end

    test "a room's chip shows only that room", %{conn: conn, bath: bath} do
      doc = page(conn, ~p"/switches?raum=#{bath.id}")

      assert ids(doc, "section.sw-room") == ["room-#{bath.id}"]
      assert ids(doc, "article") == ["sw_heater_h1"]
      assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=#{bath.id}"]
      assert hrefs(doc, "#sw_heater_h1 h3 a") == ["/switches/heaters/h1?von=#{bath.id}"]
    end

    test "„Ohne Raum“ shows only the devices without a room", %{conn: conn} do
      doc = page(conn, ~p"/switches?raum=ohne")

      assert ids(doc, "section.sw-room") == ["room-none"]
      assert ids(doc, "article") == ["light_card_NONE", "sw_card_fridge"]
      assert hrefs(doc, "#light_card_NONE h3 a") == ["/lights/NONE?von=ohne"]
    end

    test "„Alle“ shows every room", %{conn: conn, living: living, bath: bath} do
      doc = page(conn, ~p"/switches?raum=alle")

      assert ids(doc, "section.sw-room") == ["room-#{living.id}", "room-#{bath.id}", "room-none"]
      assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=alle"]
    end

    test "an unknown or empty room shows every room", %{conn: conn, living: living} do
      Repo.update_all(Light, set: [room_id: nil])

      for param <- ["quatsch", "999999", to_string(living.id), "favoriten"] do
        doc = page(conn, ~p"/switches?raum=#{param}")

        assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=alle"],
               param

        assert count(doc, "section.sw-room") == 2
      end
    end

    test "the kind filter shows its kind in all rooms, whatever view was chosen", %{
      conn: conn,
      bath: bath
    } do
      doc = page(conn, ~p"/switches?nur=lampen&raum=#{bath.id}")

      assert ids(doc, "article") == ["light_card_ABCDEF01", "light_card_NONE"]
      assert count(doc, "#sw_rooms_nav a[aria-current]") == 0
      assert count(doc, "#sw_view") == 0
    end

    test "a chip patches the view in", %{conn: conn, living: living, bath: bath} do
      {:ok, view, _html} = live(conn, ~p"/switches")

      view |> element("#sw_rooms_nav a[data-view='#{bath.id}']") |> render_click()
      assert_patched(view, ~p"/switches?raum=#{bath.id}")
      assert has_element?(view, "#sw_heater_h1")
      refute has_element?(view, "#room-#{living.id}")

      view |> element("#sw_rooms_nav a[data-view=alle]") |> render_click()
      assert_patched(view, ~p"/switches?raum=alle")
      assert has_element?(view, "#room-#{living.id}")
    end

    test "„Alle Lampen aus“ stands under „Alle“ while a lamp is lit", %{
      conn: conn,
      living: living
    } do
      doc = page(conn)
      assert text(doc, "#sw_view #sw_all_lamps_off") == "Alle Lampen aus"
      assert count(doc, "#room-#{living.id}_lamps_off") == 1

      assert count(page(conn, ~p"/switches?raum=#{living.id}"), "#sw_all_lamps_off") == 0

      Repo.update_all(State, set: [on: false])
      assert count(page(conn), "#sw_all_lamps_off") == 0
    end

    test "going back from a device's page lands on the chosen view", %{conn: conn, bath: bath} do
      {:ok, view, _html} = live(conn, ~p"/switches?raum=#{bath.id}")

      {:ok, device, _html} =
        view
        |> element("#sw_heater_h1 h3 a")
        |> render_click()
        |> follow_redirect(conn, ~p"/switches/heaters/h1?von=#{bath.id}")

      {:ok, back, _html} =
        device
        |> element("header a[href='/switches?raum=#{bath.id}']")
        |> render_click()
        |> follow_redirect(conn, ~p"/switches?raum=#{bath.id}")

      assert has_element?(back, "#sw_rooms_nav a[aria-current=true][data-view='#{bath.id}']")
    end
  end

  describe "favourites" do
    setup %{light: light} do
      living = room!("Wohnzimmer")
      bath = room!("Bad")
      Repo.update_all(Light, set: [room_id: living.id])
      heater!("h1", "Badheizung", bath)
      {:ok, _placed} = Rooms.place_plug("fridge", living.id)
      %{living: living, bath: bath, light: light}
    end

    defp star(view) do
      view |> element("#favourite") |> render_click()
      view
    end

    test "a device starred on its page stands under „Favoriten“ and stays in its room", %{
      conn: conn,
      living: living,
      bath: bath
    } do
      conn = sign_in(conn, "anna")

      for path <- [~p"/lights/ABCDEF01", ~p"/switches/heaters/h1", ~p"/switches/plugs/fridge"] do
        {:ok, view, _html} = live(conn, path)
        assert has_element?(star(view), "#favourite[aria-pressed=true]")
      end

      doc = page(conn, ~p"/switches?raum=favoriten")

      assert texts(doc, "#sw_rooms_nav a") == ["Alle", "Favoriten", "Wohnzimmer", "Bad"]
      assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=favoriten"]
      assert ids(doc, "section.sw-room") == ["favourites"]
      assert text(doc, "#favourites_heading") =~ "Favoriten"

      assert ids(doc, "#favourites article") ==
               ["light_card_ABCDEF01", "sw_card_fridge", "sw_heater_h1"]

      assert count(doc, "#favourites_lamps_off") == 0
      assert hrefs(doc, "#light_card_ABCDEF01 h3 a") == ["/lights/ABCDEF01?von=favoriten"]

      assert ids(page(conn, ~p"/switches?raum=#{living.id}"), "article") ==
               ["light_card_ABCDEF01", "sw_card_fridge"]

      assert ids(page(conn, ~p"/switches?raum=#{bath.id}"), "article") == ["sw_heater_h1"]
    end

    test "the star takes a favourite away again", %{conn: conn} do
      Residents.set_favourite("anna", {:lamp, "ABCDEF01"}, true)
      conn = sign_in(conn, "anna")

      {:ok, view, _html} = live(conn, ~p"/lights/ABCDEF01")
      assert has_element?(view, "#favourite[aria-pressed=true]")
      assert has_element?(star(view), "#favourite[aria-pressed=false]")

      assert texts(page(conn), "#sw_rooms_nav a") == ["Alle", "Wohnzimmer", "Bad"]
    end

    test "without favourites there is no chip, and „Favoriten“ shows every room", %{conn: conn} do
      Residents.set_favourite("anna", {:lamp, "GONE"}, true)
      doc = conn |> sign_in("anna") |> page(~p"/switches?raum=favoriten")

      refute "Favoriten" in texts(doc, "#sw_rooms_nav a")
      assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=alle"]
    end

    # Scenario: Two residents, one device
    test "another resident's favourite is not among one's own", %{conn: conn} do
      {:ok, view, _html} = conn |> sign_in("anna") |> live(~p"/lights/ABCDEF01")
      star(view)

      doc = build_conn() |> sign_in("ben") |> page(~p"/switches?raum=favoriten")

      refute "Favoriten" in texts(doc, "#sw_rooms_nav a")
      assert count(doc, "#favourites") == 0
      assert Residents.favourites("ben") == MapSet.new()
    end

    test "the star is only for a signed-in resident", %{conn: conn} do
      for path <- [~p"/lights/ABCDEF01", ~p"/switches/heaters/h1", ~p"/switches/plugs/fridge"] do
        {:ok, view, _html} = live(conn, path)
        refute has_element?(view, "#favourite")
        render_hook(view, "toggle_favourite", %{})
      end

      assert Repo.aggregate(Residents.Favourite, :count) == 0
    end
  end

  describe "the default view" do
    setup do
      office = room!("Büro")
      Repo.update_all(Light, set: [room_id: office.id])
      %{office: office}
    end

    test "„Als Standard“ makes Schalten open with the view next time", %{
      conn: conn,
      office: office
    } do
      conn = sign_in(conn, "anna")
      {:ok, view, _html} = live(conn, ~p"/switches?raum=#{office.id}")

      view |> element("#sw_set_default") |> render_click()
      assert has_element?(view, "#sw_default", "Deine Standardansicht")
      refute has_element?(view, "#sw_set_default")

      doc = page(conn)
      assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=#{office.id}"]
      assert ids(doc, "section.sw-room") == ["room-#{office.id}"]

      assert hrefs(page(conn, ~p"/switches?raum=alle"), "#sw_rooms_nav a[aria-current=true]") ==
               ["/switches?raum=alle"]

      doc = build_conn() |> sign_in("ben") |> page()
      assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=alle"]
    end

    test "„Alle“ can be the default again, „Ohne Raum“ and the filter offer none", %{
      conn: conn,
      office: office
    } do
      Residents.set_default_view("anna", {:room, office.id})
      conn = sign_in(conn, "anna")
      {:ok, view, _html} = live(conn, ~p"/switches?raum=alle")

      view |> element("#sw_set_default") |> render_click()
      assert Residents.default_view("anna") == :all
      assert has_element?(view, "#sw_default")

      assert count(page(conn, ~p"/switches?raum=ohne"), "#sw_view") == 0
      assert count(page(conn, ~p"/switches?nur=steckdosen"), "#sw_view") == 0

      render_hook(view, "set_default", %{"view" => "ohne"})
      render_hook(view, "set_default", %{"view" => "999999"})
      assert Residents.default_view("anna") == :all
    end

    test "„Alle zeigen“ leads back to the default view", %{conn: conn, office: office} do
      Residents.set_default_view("anna", {:room, office.id})
      doc = conn |> sign_in("anna") |> page(~p"/switches?nur=lampen")

      assert hrefs(doc, "#sw_filter a") == ["/switches"]
    end

    # Scenario: The default view no longer exists
    test "a deleted room's default opens with „Alle“", %{conn: conn, office: office} do
      Residents.set_default_view("anna", {:room, office.id})
      {:ok, _deleted} = Rooms.delete(office)

      doc = conn |> sign_in("anna") |> page()

      assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=alle"]
    end

    # Scenario: The last favourite is removed
    test "without its last favourite „Favoriten“ is gone and Schalten opens with „Alle“", %{
      conn: conn
    } do
      Residents.set_default_view("anna", :favourites)
      Residents.set_favourite("anna", {:lamp, "ABCDEF01"}, true)
      conn = sign_in(conn, "anna")

      doc = page(conn)
      assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=favoriten"]
      assert count(doc, "#sw_default") == 1

      {:ok, lamp, _html} = live(conn, ~p"/lights/ABCDEF01")
      lamp |> element("#favourite") |> render_click()

      doc = page(conn)
      refute "Favoriten" in texts(doc, "#sw_rooms_nav a")
      assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=alle"]
      assert count(doc, "#sw_set_default") == 1
    end

    # Scenario: An identity that does not come from the gate
    test "a name from anywhere but the trusted proxy gets the shared view", %{
      conn: conn,
      office: office
    } do
      Residents.set_default_view("anna", {:room, office.id})
      Residents.set_favourite("anna", {:lamp, "ABCDEF01"}, true)
      conn = %{sign_in(conn, "anna") | remote_ip: {192, 168, 1, 23}}

      doc = page(conn)
      assert hrefs(doc, "#sw_rooms_nav a[aria-current=true]") == ["/switches?raum=alle"]
      refute "Favoriten" in texts(doc, "#sw_rooms_nav a")
      assert count(doc, "#sw_set_default, #sw_default, [data-resident]") == 0

      {:ok, lamp, _html} = live(conn, ~p"/lights/ABCDEF01")
      refute has_element?(lamp, "#favourite")
    end

    test "without the header Schalten opens with „Alle“ and switches", %{conn: conn} do
      start_supervised!({FakeGoveeBridge, test: self()})
      {:ok, view, _html} = live(conn, ~p"/switches")

      assert has_element?(view, "#sw_rooms_nav a[aria-current=true][data-view=alle]")
      refute has_element?(view, "#sw_set_default")
      refute has_element?(view, "#sw_default")

      view |> element("#light_card_ABCDEF01 button.sw-knob") |> render_click()
      render_async(view)
      assert_received {:govee, "ABCDEF01", {:power, false}}
    end
  end

  describe "the summaries" do
    test "say per kind what is on and link to the kind's filter", %{conn: conn} do
      heater!("h1", "Badheizung")
      insert_sample!("fridge", unix_now(), 84.4, 1)
      state!(true)
      doc = page(conn)

      assert ids(doc, "#sw_summary a") ==
               ~w[sw_summary_lampen sw_summary_heizungen sw_summary_steckdosen]

      assert text(doc, "#sw_summary_lampen") == "Lampen 1 an"
      assert text(doc, "#sw_summary_heizungen") == "Heizungen Frostschutz"
      assert text(doc, "#sw_summary_steckdosen") == "Steckdosen 1 an · 84 W"

      assert hrefs(doc, "#sw_summary a") ==
               ~w[/switches?nur=lampen /switches?nur=heizungen /switches?nur=steckdosen]

      assert count(doc, "#sw_summary a[aria-current]") == 0
    end

    test "say „alle aus“ when nothing of a kind is on", %{conn: conn} do
      Repo.update_all(State, set: [on: false])
      insert_sample!("fridge", unix_now(), 0, 1)
      state!(false)
      doc = page(conn)

      assert text(doc, "#sw_summary_lampen [data-summary]") == "alle aus"
      assert text(doc, "#sw_summary_steckdosen [data-summary]") == "alle aus"
      assert count(doc, "#sw_summary_heizungen") == 0
    end
  end

  describe "the kind filter" do
    test "?nur=lampen shows only lamps, in all their rooms", %{conn: conn} do
      room = room!("Wohnzimmer")
      Repo.update_all(Light, set: [room_id: room.id])
      lamp!("LAMP2", "Leselampe", false)
      heater!("h1", "Heizung", room)

      doc = page(conn, ~p"/switches?nur=lampen")

      assert text(doc, "#sw_filter") =~ "Nur Lampen, alle Räume"
      assert ids(doc, "article") == ["light_card_ABCDEF01", "light_card_LAMP2"]
      assert ids(doc, "section.sw-room") == ["room-#{room.id}", "room-none"]
      assert count(doc, "#sw_summary_lampen[aria-current=true][href='/switches']") == 1
      assert text(doc, "#sw_all_lamps_off") == "Alle Lampen aus"
      assert count(doc, "#sw_filter a[href='/switches']") == 1
    end

    test "?nur=steckdosen and ?nur=heizungen show only their kind", %{conn: conn} do
      heater!("h1", "Heizung")

      assert ids(page(conn, ~p"/switches?nur=steckdosen"), "article") == ["sw_card_fridge"]
      assert ids(page(conn, ~p"/switches?nur=heizungen"), "article") == ["sw_heater_h1"]

      doc = page(conn, ~p"/switches?nur=steckdosen")
      assert text(doc, "#sw_filter") =~ "Nur Steckdosen, alle Räume"
      assert count(doc, "#sw_all_lamps_off") == 0
    end

    test "„Alle Lampen aus“ needs a lit lamp; an unknown filter shows everything", %{conn: conn} do
      Repo.update_all(State, set: [on: false])
      assert count(page(conn, ~p"/switches?nur=lampen"), "#sw_all_lamps_off") == 0

      doc = page(conn, ~p"/switches?nur=quatsch")
      assert count(doc, "#sw_filter") == 0
      assert ids(doc, "article") == ["light_card_ABCDEF01", "sw_card_fridge"]
    end

    test "a summary patches the filter in and out", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/switches")

      view |> element("#sw_summary_steckdosen") |> render_click()
      assert_patched(view, ~p"/switches?nur=steckdosen")
      refute has_element?(view, "#light_card_ABCDEF01")
      assert has_element?(view, "#sw_card_fridge")

      view |> element("#sw_summary_steckdosen") |> render_click()
      assert_patched(view, ~p"/switches")
      assert has_element?(view, "#light_card_ABCDEF01")
    end
  end

  describe "Lampen aus" do
    setup do
      start_supervised!({FakeGoveeBridge, test: self()})
      :ok
    end

    test "turns off only the lit lamps of its room", %{conn: conn} do
      living = room!("Wohnzimmer")
      bath = room!("Bad")
      Repo.update_all(Light, set: [room_id: living.id])
      lamp!("LIT2", "Leselampe", true, living)
      lamp!("DARK", "Nachtlicht", false, living)
      lamp!("BATH", "Spiegel", true, bath)
      lamp!("NONE", "Flur", true)

      {:ok, view, _html} = live(conn, ~p"/switches")
      view |> element("#room-#{living.id}_lamps_off") |> render_click()
      render_async(view)

      assert_received {:govee, "ABCDEF01", {:power, false}}
      assert_received {:govee, "LIT2", {:power, false}}
      refute_received {:govee, _key, _verb}

      refute has_element?(view, "#room-#{living.id}_lamps_off")
      assert has_element?(view, "#room-#{living.id}_heading [data-on-count]", "alles aus")
      assert has_element?(view, "#room-#{bath.id}_lamps_off")
      assert has_element?(view, "#room-none_lamps_off")
    end

    test "„Ohne Raum“ turns off the lamps without a room", %{conn: conn} do
      room = room!("Bad")
      lamp!("BATH", "Spiegel", true, room)

      {:ok, view, _html} = live(conn, ~p"/switches")
      view |> element("#room-none_lamps_off") |> render_click()
      render_async(view)

      assert_received {:govee, "ABCDEF01", {:power, false}}
      refute_received {:govee, "BATH", _verb}
    end

    test "„Alle Lampen aus“ turns off every lit lamp", %{conn: conn} do
      room = room!("Bad")
      lamp!("BATH", "Spiegel", true, room)
      lamp!("DARK", "Nachtlicht", false, room)

      {:ok, view, _html} = live(conn, ~p"/switches?nur=lampen")
      view |> element("#sw_all_lamps_off") |> render_click()
      render_async(view)

      assert_received {:govee, "ABCDEF01", {:power, false}}
      assert_received {:govee, "BATH", {:power, false}}
      refute_received {:govee, _key, _verb}
      refute has_element?(view, "#sw_all_lamps_off")
    end

    test "never switches a plug, not even the one that powers a lit lamp", %{conn: conn} do
      FakeShelly.serve("fridge")
      state!(true)
      insert_sample!("fridge", unix_now(), 84.0, 1)
      living = room!("Wohnzimmer")
      Repo.update_all(Light, set: [room_id: living.id, shelly_plug_id: "fridge"])
      {:ok, _placed} = Rooms.place_plug("fridge", living.id)

      {:ok, view, _html} = live(conn, ~p"/switches")
      view |> element("#room-#{living.id}_lamps_off") |> render_click()
      render_hook(view, "lamps_off", %{"room" => "all"})
      render_hook(view, "lamps_off", %{"room" => "none"})
      render_async(view)

      assert_received {:govee, "ABCDEF01", {:power, false}}
      refute_received {:shelly_rpc, "fridge", "Switch.Set", _params}
      assert has_element?(view, "#sw_card_fridge button[aria-pressed=true]")
    end

    test "„Ohne Raum“ also takes a lamp whose room the page does not know yet", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/switches")
      room = room!("Flur")
      Repo.update_all(Light, set: [room_id: room.id])
      send(view.pid, {:updated, "ABCDEF01"})
      assert has_element?(view, "#room-none #light_card_ABCDEF01")

      view |> element("#room-none_lamps_off") |> render_click()
      render_async(view)

      assert_received {:govee, "ABCDEF01", {:power, false}}
    end

    test "a room without a lit lamp has no button, and a crafted press does nothing", %{
      conn: conn
    } do
      room = room!("Bad")
      lamp!("DARK", "Nachtlicht", false, room)

      {:ok, view, _html} = live(conn, ~p"/switches")
      refute has_element?(view, "#room-#{room.id}_lamps_off")

      render_hook(view, "lamps_off", %{"room" => to_string(room.id)})
      render_hook(view, "lamps_off", %{"room" => "nope"})
      render_async(view)

      refute_received {:govee, _key, _verb}
    end
  end

  test "a filter for a kind the home has none of shows everything", %{conn: conn} do
    doc = page(conn, ~p"/switches?nur=heizungen")

    assert count(doc, "#sw_filter") == 0
    assert count(doc, "#light_card_ABCDEF01") == 1
    assert count(doc, "#sw_card_fridge") == 1
  end

  describe "room air" do
    test "shows under a room named like a sensor's room", %{conn: conn} do
      reading!(temperature: 21.0, humidity: 50.0, co2: 1200, battery_pct: 90)
      living = room!("Wohnzimmer")
      kitchen = room!("Küche")
      Repo.update_all(Light, set: [room_id: living.id])
      {:ok, _placed} = Rooms.place_plug("fridge", kitchen.id)

      doc = page(conn)

      assert text(doc, "#room-#{living.id} [data-air] a[href='/sensors']") ==
               "21,0 °C · CO₂ 1.200 ppm"

      assert text(doc, "#room-#{living.id} [data-air] .badge") == "Bald lüften"
      assert count(doc, "#room-#{kitchen.id} [data-air]") == 0
      assert count(doc, "#room-none [data-air]") == 0
    end

    test "good air shows the values without a badge", %{conn: conn} do
      reading!(temperature: 20.5, humidity: 45.0, co2: 600, battery_pct: 90)
      living = room!("Wohnzimmer")
      Repo.update_all(Light, set: [room_id: living.id])

      doc = page(conn)
      assert text(doc, "#room-#{living.id} [data-air]") == "20,5 °C · CO₂ 600 ppm"
      assert count(doc, "#room-#{living.id} [data-air] .badge") == 0
    end

    test "a new reading updates the room's air on an open page", %{conn: conn} do
      living = room!("Wohnzimmer")
      Repo.update_all(Light, set: [room_id: living.id])
      {:ok, view, _html} = live(conn, ~p"/switches")
      refute has_element?(view, "#room-#{living.id} [data-air]")

      {:ok, _reading} =
        Sensors.create_reading("TEST_INDOOR", Clock.parse!(@now), %{temperature: 19.5, co2: 700})

      assert has_element?(view, "#room-#{living.id} [data-air]", ~r/19,5 °C\W+CO₂ 700 ppm/u)
    end
  end
end
