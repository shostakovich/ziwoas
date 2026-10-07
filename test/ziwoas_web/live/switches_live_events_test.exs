defmodule ZiwoasWeb.SwitchesLiveEventsTest do
  # The Schalten page served by Phoenix: the controls Rails drives through Turbo work as
  # LiveView events (plug button, lamp tile, the inline schedule editors), each only as
  # owner of its task.
  use ZiwoasWeb.ConnCase, async: true, db: true

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Mqtt, Ownership, Repo}
  alias Ziwoas.Lights.Light
  alias Ziwoas.Switching.{Command, Rule, Rules}

  setup %{repo: repo} do
    Clock.freeze("2026-06-15T17:00:00+02:00")
    Repo.put_writer(:main, repo)
    Ownership.override(%{switching: :phoenix, lights: :phoenix, switch_schedule: :phoenix})
    on_exit(&Ownership.clear_override/0)

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

    Mqtt.record(fn _client, topic, payload ->
      send(test, {:published, topic, payload})
      answer
    end)
  end

  defp rules, do: Repo.all(from r in Rule, order_by: [r.at_minute, r.id])

  describe "the plug button" do
    test "switches by hand and redraws the head", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/switches")
      html = view |> form("#sw_head_fridge form") |> render_submit()

      assert_received {:published, "shellies/fridge/command/switch:0", "on"}
      assert [%Command{action: "on", source: "manual"}] = Repo.all(Command)
      assert html =~ "An seit 17:00 (manuell)"
      assert has_element?(view, "#sw_head_fridge form[action='/plugs/fridge/switch?state=off']")
    end

    test "shows the broker error in the head", %{conn: conn} do
      record({:error, :timeout})
      {:ok, view, _html} = live(conn, ~p"/switches")
      view |> form("#sw_head_fridge form") |> render_submit()

      assert view |> element("#sw_error_fridge") |> render() =~
               "Schalten fehlgeschlagen — MQTT-Broker nicht erreichbar"

      assert Repo.all(Command) == []
    end

    test "switches nothing while Phoenix does not own switching", %{conn: conn} do
      Ownership.override(%{switching: :dry_run})
      {:ok, view, _html} = live(conn, ~p"/switches")
      view |> form("#sw_head_fridge form") |> render_submit()

      refute_received {:published, _, _}
      assert Repo.all(Command) == []
      assert view |> element("#sw_error_fridge") |> render() =~ "nicht zuständig"
    end
  end

  test "the lamp tile turns its lamp", %{conn: conn} do
    Repo.insert!(%Light{key: "ABCDEF01", name: "Stehlampe", sku: "H607C"})
    {:ok, view, _html} = live(conn, ~p"/switches")
    html = view |> form("#light_card_ABCDEF01 form") |> render_submit()

    assert_received {:published, "govees/ABCDEF01/set", ~s({"power":"on"})}
    assert html =~ "An · Weiß"
  end

  describe "the schedule editors" do
    test "a new Zeitfenster: the editor opens, refuses, then saves and closes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/switches")
      view |> element("#sw_rules_fridge a", "+ Zeitfenster") |> render_click()
      assert has_element?(view, "#sw_editor_fridge form[phx-submit=save_entry]")

      html =
        view
        |> form("#sw_editor_fridge form", %{
          "switch_window" => %{"on_at_time" => "18:00", "off_at_time" => "18:00", "days" => ["1"]}
        })
        |> render_submit()

      assert html =~ "An- und Aus-Zeit müssen sich unterscheiden"
      assert rules() == []

      view
      |> form("#sw_editor_fridge form", %{
        "switch_window" => %{"on_at_time" => "22:00", "off_at_time" => "06:00", "days" => ["1"]}
      })
      |> render_submit()

      assert [%Rule{action: "off", at_minute: 360, days: [2]}, %Rule{action: "on", days: [1]}] =
               rules()

      refute has_element?(view, "#sw_editor_fridge form")
      assert render(view) =~ "Mo · 22:00–06:00"
    end

    test "a new Einzelschaltung", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/switches")
      view |> element("#sw_rules_fridge a", "+ Einzelschaltung") |> render_click()

      view
      |> form("#sw_editor_fridge form", %{
        "switch_rule" => %{"at_minute_time" => "07:30", "action" => "on", "days" => ["6", "7"]}
      })
      |> render_submit()

      assert [%Rule{action: "on", at_minute: 450, days: [6, 7], group_id: nil}] = rules()
    end

    test "edit in place, pause and delete a Zeitfenster", %{conn: conn} do
      group =
        Rules.save_window("fridge", %{on_at_time: "18:00", off_at_time: "23:00", days: [1, 2]})

      {:ok, view, _html} = live(conn, ~p"/switches")
      view |> element("#sw_entry_fridge_#{group} a[phx-click=edit_entry]") |> render_click()
      assert has_element?(view, "#sw_entry_fridge_#{group} form[phx-submit=save_entry]")

      view
      |> form("#sw_entry_fridge_#{group} form", %{
        "switch_window" => %{"on_at_time" => "09:00", "off_at_time" => "17:00", "days" => ["6"]}
      })
      |> render_submit()

      assert [%Rule{at_minute: 540, days: [6]}, %Rule{at_minute: 1020, days: [6]}] = rules()

      view |> form("#sw_entry_fridge_#{group} form[phx-submit=set_enabled]") |> render_submit()
      assert Enum.all?(rules(), &(not &1.enabled))

      view |> form("#sw_entry_fridge_#{group} form[phx-submit=delete_entry]") |> render_submit()
      assert rules() == []
    end

    test "an Einzelschaltung pauses and resumes", %{conn: conn} do
      rule = Rules.save_single("fridge", %{action: "off", at_minute_time: "22:00", days: [1]})
      {:ok, view, _html} = live(conn, ~p"/switches")

      view |> form("#sw_entry_fridge_#{rule.id} form[phx-submit=set_enabled]") |> render_submit()
      refute Repo.get!(Rule, rule.id).enabled
      view |> form("#sw_entry_fridge_#{rule.id} form[phx-submit=set_enabled]") |> render_submit()
      assert Repo.get!(Rule, rule.id).enabled
    end

    test "nothing is written while Phoenix does not own the schedule", %{conn: conn} do
      rule = Rules.save_single("fridge", %{action: "off", at_minute_time: "22:00", days: [1]})
      Ownership.override(%{switch_schedule: :rails})
      {:ok, view, _html} = live(conn, ~p"/switches")

      view |> form("#sw_entry_fridge_#{rule.id} form[phx-submit=delete_entry]") |> render_submit()
      assert [%Rule{}] = rules()
    end
  end
end
