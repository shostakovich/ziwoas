defmodule ZiwoasWeb.SwitchesLiveEventsTest do
  # The Schalten page's controls: the plug button, the lamp tile and the inline
  # schedule editor. The broker is TestMqtt; nothing reaches a device.
  use ZiwoasWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Repo, TestClock, TestMqtt}
  alias Ziwoas.Lights.Light
  alias Ziwoas.Switching.{Command, Rule, Rules}

  setup do
    TestClock.freeze("2026-06-15T17:00:00+02:00")

    Repo.insert!(%Ziwoas.Plugs.Sample{
      plug_id: "fridge",
      ts: Clock.unix_now() - 5,
      apower_w: 1.0,
      aenergy_wh: 1.0
    })

    record(:ok)
    :ok
  end

  defp record(answer) do
    test = self()

    TestMqtt.record(fn _client, topic, payload ->
      send(test, {:published, topic, payload})
      answer
    end)
  end

  defp rules, do: Repo.all(from r in Rule, order_by: [r.at_minute, r.id])

  defp a_window(on \\ "18:00", off \\ "23:00", days \\ [1, 2]) do
    {:ok, group_id} =
      Rules.save_window("fridge", %{on_at_time: on, off_at_time: off, days: days})

    group_id
  end

  defp a_single do
    {:ok, rule} =
      Rules.save_single("fridge", %{at_minute_time: "22:00", action: "off", days: [1]})

    rule
  end

  defp window_params(on, off, days),
    do: %{"window" => %{"on_at_time" => on, "off_at_time" => off, "days" => days}}

  defp rule_params(at, action, days),
    do: %{"rule" => %{"at_minute_time" => at, "action" => action, "days" => days}}

  defp open_page(conn) do
    {:ok, view, _html} = live(conn, ~p"/switches")
    view
  end

  defp new_entry(view, label),
    do: view |> element("#sw_rules_fridge button", label) |> render_click()

  defp entry_button(view, id, event),
    do: element(view, "#sw_entry_fridge_#{id} button[phx-click=#{event}]")

  defp checked_days(view, form),
    do:
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#{form} input[type=checkbox][checked]")
      |> LazyHTML.attribute("value")

  describe "the plug button" do
    test "switches by hand, logs a manual command and redraws the head", %{conn: conn} do
      view = open_page(conn)
      html = view |> element("#sw_head_fridge button[phx-click=switch_plug]") |> render_click()

      assert_received {:published, "shellies/fridge/command/switch:0", "on"}
      assert [%Command{action: "on", source: "manual"}] = Repo.all(Command)
      assert html =~ "An seit 17:00 (manuell)"

      assert has_element?(
               view,
               "#sw_head_fridge button[phx-click=switch_plug][phx-value-state=off]"
             )
    end

    test "a broker failure is a flash and logs nothing", %{conn: conn} do
      record({:error, :timeout})
      view = open_page(conn)
      view |> element("#sw_head_fridge button[phx-click=switch_plug]") |> render_click()

      assert render(view) =~ "Kühlschrank: Schalten fehlgeschlagen — MQTT-Broker nicht erreichbar"
      assert Repo.all(Command) == []
    end

    test "an unknown plug, a plug that does not switch and an invalid state do nothing", %{
      conn: conn
    } do
      view = open_page(conn)

      for params <- [
            %{"plug_id" => "nope", "state" => "on"},
            %{"plug_id" => "bkw", "state" => "on"},
            %{"plug_id" => "fridge", "state" => "toggle"},
            %{"plug_id" => "fridge"}
          ],
          do: render_hook(view, "switch_plug", params)

      refute_received {:published, _, _}
      assert Repo.all(Command) == []
    end
  end

  describe "the lamp tile" do
    setup do
      %{light: Repo.insert!(%Light{key: "ABCDEF01", name: "Stehlampe", sku: "H607C"})}
    end

    test "turns its lamp", %{conn: conn} do
      view = open_page(conn)
      html = view |> element("#light_card_ABCDEF01 button.sw-knob") |> render_click()

      assert_received {:published, "govees/ABCDEF01/set", ~s({"power":"on"})}
      assert html =~ "An · Weiß"
    end

    test "a broker failure is a flash", %{conn: conn} do
      record({:error, :closed})
      view = open_page(conn)
      view |> element("#light_card_ABCDEF01 button.sw-knob") |> render_click()

      assert render(view) =~ "Lampe nicht erreichbar"
    end

    test "an unknown lamp or command does nothing", %{conn: conn} do
      view = open_page(conn)
      render_hook(view, "light_command", %{"light_key" => "nope", "command" => "turn"})
      render_hook(view, "light_command", %{"light_key" => "ABCDEF01", "command" => "explode"})
      refute_received {:published, _, _}
    end
  end

  describe "a new Zeitfenster" do
    test "the editor offers two times and the weekdays as toggle buttons", %{conn: conn} do
      view = open_page(conn)
      new_entry(view, "+ Zeitfenster")

      assert has_element?(view, "#sw_editor_fridge form[phx-submit=save_entry]")
      assert has_element?(view, "#sw_editor_fridge input#sw_fridge_new_on_at_time[type=time]")
      assert has_element?(view, "#sw_editor_fridge input#sw_fridge_new_off_at_time[type=time]")

      doc = view |> render() |> LazyHTML.from_document()

      assert doc
             |> LazyHTML.query(
               "[role=group][aria-label=Wochentage] input.btn-check[type=checkbox][name='window[days][]']"
             )
             |> Enum.count() == 7

      assert doc
             |> LazyHTML.query("input[type=hidden][name='window[days][]'][value='']")
             |> Enum.count() == 1
    end

    test "refuses as it is typed and on save, then saves, closes and says so", %{conn: conn} do
      view = open_page(conn)
      new_entry(view, "+ Zeitfenster")
      form = "#sw_editor_fridge form"

      html = view |> form(form, window_params("18:00", "18:00", ["", "1"])) |> render_change()
      assert html =~ "An- und Aus-Zeit müssen sich unterscheiden"

      html = view |> form(form, window_params("18:00", "19:00", [""])) |> render_submit()
      assert html =~ "mindestens ein Wochentag muss gewählt sein"
      assert rules() == []

      view |> form(form, window_params("22:00", "06:00", ["", "1"])) |> render_submit()

      assert [%Rule{action: "off", at_minute: 360, days: [2]}, %Rule{action: "on", days: [1]}] =
               rules()

      refute has_element?(view, "#sw_editor_fridge form")
      assert render(view) =~ "Mo · 22:00–06:00"
      assert render(view) =~ "Zeitfenster gespeichert."
      assert view |> element("#sw_card_fridge summary") |> render() =~ "Schaltzeiten (2)"
    end

    test "a refused form keeps what was typed", %{conn: conn} do
      view = open_page(conn)
      new_entry(view, "+ Zeitfenster")

      view
      |> form("#sw_editor_fridge form", window_params("", "25:00", ["", "1"]))
      |> render_submit()

      assert view |> element("#sw_fridge_new_off_at_time") |> render() =~ ~s(value="25:00")
      assert view |> render() =~ "Uhrzeit im Format HH:MM angeben"
      assert checked_days(view, "#sw_editor_fridge") == ["1"]
    end

    test "Abbrechen closes the editor", %{conn: conn} do
      view = open_page(conn)
      new_entry(view, "+ Zeitfenster")
      view |> element("#sw_editor_fridge button", "Abbrechen") |> render_click()
      refute has_element?(view, "#sw_editor_fridge form")
    end
  end

  describe "a new Einzelschaltung" do
    test "offers the direction, off by default, and saves one rule without a group", %{
      conn: conn
    } do
      view = open_page(conn)
      new_entry(view, "+ Einzelschaltung")

      assert has_element?(
               view,
               "[role=group][aria-label=Richtung] input.btn-check[type=radio][name='rule[action]'][value=off][checked]"
             )

      assert view |> element("label[for=sw_fridge_new_day_1]") |> render() =~ "Mo"

      view
      |> form("#sw_editor_fridge form", rule_params("07:30", "on", ["", "6", "7"]))
      |> render_submit()

      assert [%Rule{action: "on", at_minute: 450, days: [6, 7], group_id: nil, enabled: true}] =
               rules()

      assert render(view) =~ "Schaltzeit gespeichert."
    end

    test "refuses a direction that is neither on nor off", %{conn: conn} do
      view = open_page(conn)
      new_entry(view, "+ Einzelschaltung")

      html =
        view
        |> form("#sw_editor_fridge form")
        |> render_submit(rule_params("22:00", "toggle", ["1"]))

      assert html =~ "Richtung muss an oder aus sein"
      assert rules() == []
    end
  end

  describe "an existing Zeitfenster" do
    test "is edited in place, keeping its rule ids", %{conn: conn} do
      group = a_window()
      ids = Enum.map(rules(), & &1.id)
      view = open_page(conn)

      view |> entry_button(group, "edit_entry") |> render_click()
      assert has_element?(view, "#sw_entry_fridge_#{group} form[phx-submit=save_entry]")
      assert view |> element("#sw_fridge_#{group}_on_at_time") |> render() =~ ~s(value="18:00")

      view
      |> form("#sw_entry_fridge_#{group} form", window_params("09:00", "17:00", ["", "6"]))
      |> render_submit()

      assert [%Rule{at_minute: 540, days: [6]}, %Rule{at_minute: 1020, days: [6]}] = rules()
      assert Enum.sort(Enum.map(rules(), & &1.id)) == Enum.sort(ids)
      refute has_element?(view, "#sw_entry_fridge_#{group} form")
    end

    test "past midnight shows the times and days that were typed", %{conn: conn} do
      group = a_window("22:00", "06:00", [1, 2, 3, 4, 5])
      view = open_page(conn)
      view |> entry_button(group, "edit_entry") |> render_click()

      assert checked_days(view, "#sw_entry_fridge_#{group}") == ~w[1 2 3 4 5]
    end

    test "a refused update stays in its row and changes nothing", %{conn: conn} do
      group = a_window()
      view = open_page(conn)
      view |> entry_button(group, "edit_entry") |> render_click()

      html =
        view
        |> form("#sw_entry_fridge_#{group} form", window_params("", "23:00", ["1"]))
        |> render_submit()

      assert html =~ "Uhrzeit im Format HH:MM angeben"
      assert has_element?(view, "#sw_entry_fridge_#{group} form")
      assert Enum.map(rules(), & &1.at_minute) == [1080, 1380]
    end

    test "pauses and resumes both halves, and is deleted as a whole", %{conn: conn} do
      group = a_window()
      view = open_page(conn)

      view |> entry_button(group, "set_enabled") |> render_click()
      assert Enum.map(rules(), & &1.enabled) == [false, false]
      view |> entry_button(group, "set_enabled") |> render_click()
      assert Enum.map(rules(), & &1.enabled) == [true, true]

      view |> entry_button(group, "delete_entry") |> render_click()
      assert rules() == []
      assert render(view) =~ "Zeitfenster gelöscht."
    end

    test "a group that left this plug or lost a half is no Zeitfenster here", %{conn: conn} do
      group = a_window()
      view = open_page(conn)
      Repo.update_all(Rule, set: [plug_id: "gone"])

      params = %{"plug_id" => "fridge", "kind" => "window", "id" => group}
      render_hook(view, "edit_entry", params)
      render_hook(view, "set_enabled", Map.put(params, "enabled", "false"))
      render_hook(view, "delete_entry", params)

      refute has_element?(view, "form[phx-submit=save_entry]")
      assert Enum.map(rules(), & &1.enabled) == [true, true]
      refute render(view) =~ "gelöscht"

      Repo.update_all(Rule, set: [plug_id: "fridge"])
      Repo.delete_all(from r in Rule, where: r.action == "off")
      render_hook(view, "edit_entry", params)
      refute has_element?(view, "form[phx-submit=save_entry]")
    end
  end

  describe "an existing Einzelschaltung" do
    test "is edited in place and stays paused", %{conn: conn} do
      rule = a_single()
      Rules.set_enabled([rule], false)
      view = open_page(conn)

      view |> entry_button(rule.id, "edit_entry") |> render_click()

      view
      |> form("#sw_entry_fridge_#{rule.id} form", rule_params("07:30", "on", ["", "6", "7"]))
      |> render_submit()

      assert [%Rule{action: "on", at_minute: 450, days: [6, 7], enabled: false}] = rules()
    end

    test "pauses, resumes and is deleted", %{conn: conn} do
      rule = a_single()
      view = open_page(conn)

      view |> entry_button(rule.id, "set_enabled") |> render_click()
      refute Repo.get!(Rule, rule.id).enabled
      view |> entry_button(rule.id, "set_enabled") |> render_click()
      assert Repo.get!(Rule, rule.id).enabled

      view |> entry_button(rule.id, "delete_entry") |> render_click()
      assert rules() == []
      assert render(view) =~ "Schaltzeit gelöscht."
    end

    test "one half of an intact Zeitfenster is not addressable as one", %{conn: conn} do
      a_window()
      half = Repo.one(from r in Rule, where: r.action == "off")
      view = open_page(conn)

      params = %{"plug_id" => "fridge", "kind" => "rule", "id" => to_string(half.id)}
      render_hook(view, "edit_entry", params)
      render_hook(view, "set_enabled", Map.put(params, "enabled", "false"))
      render_hook(view, "delete_entry", params)

      refute has_element?(view, "form[phx-submit=save_entry]")
      assert Repo.get!(Rule, half.id).enabled
      assert length(rules()) == 2
    end

    test "the half a group left over is edited and deleted as an Einzelschaltung", %{conn: conn} do
      group = a_window()
      Repo.delete_all(from r in Rule, where: r.group_id == ^group and r.action == "on")
      orphan = Repo.one(Rule)
      view = open_page(conn)

      view |> entry_button(orphan.id, "edit_entry") |> render_click()
      assert has_element?(view, "#sw_entry_fridge_#{orphan.id} form[phx-submit=save_entry]")
      view |> element("#sw_entry_fridge_#{orphan.id} button", "Abbrechen") |> render_click()

      view |> entry_button(orphan.id, "delete_entry") |> render_click()
      assert rules() == []
    end
  end
end
