defmodule ZiwoasWeb.SwitchRuleControllerTest do
  # Mirrors test/controllers/switch_rules_controller_test.rb.
  use ZiwoasWeb.ConnCase, async: true, db: true

  import Ecto.Query
  import ZiwoasWeb.TurboCase

  alias Ziwoas.{Clock, Ownership, Repo}
  alias Ziwoas.Switching.{Rule, Rules}

  setup %{repo: repo, conn: conn} do
    Clock.freeze("2026-06-15T17:00:00+02:00")
    Repo.put_writer(:main, repo)
    Ownership.override(%{switch_schedule: :phoenix})
    on_exit(&Ownership.clear_override/0)
    {:ok, conn: turbo(conn)}
  end

  @valid %{
    "switch_rule" => %{"at_minute_time" => "22:00", "action" => "off", "days" => ["", "1", "2"]}
  }

  defp a_single(opts \\ []) do
    Rules.save_single("fridge", %{
      at_minute_time: Keyword.get(opts, :at, "22:00"),
      action: Keyword.get(opts, :action, "off"),
      days: [1]
    })
  end

  defp a_window,
    do: Rules.save_window("fridge", %{on_at_time: "10:00", off_at_time: "20:00", days: [1]})

  defp params(at, action, days),
    do: %{"switch_rule" => %{"at_minute_time" => at, "action" => action, "days" => days}}

  defp reload(rule), do: Repo.get(Rule, rule.id)

  test "new offers the direction and the weekdays as toggle buttons", %{conn: conn} do
    body = conn |> get(~p"/plugs/fridge/switch_rules/new") |> stream_response(200)
    doc = stream_doc(body)

    assert streams(body) == [{"update", "sw_editor_fridge"}]

    assert count(
             doc,
             "[role=group][aria-label=Richtung] input.btn-check[type=radio][name='switch_rule[action]']"
           ) == 2

    assert LazyHTML.text(LazyHTML.query(doc, "label[for=sw_fridge_new_action_on]")) =~ "an"
    assert count(doc, "[role=group][aria-label=Wochentage] input.btn-check[type=checkbox]") == 7
    assert LazyHTML.text(LazyHTML.query(doc, "label[for=sw_day_fridge_new_1]")) == "Mo"
    # A new Einzelschaltung switches off unless told otherwise.
    assert doc |> LazyHTML.query("input[type=radio][checked]") |> LazyHTML.attribute("value") == [
             "off"
           ]
  end

  test "create writes one rule without a group and re-renders the rules region", %{conn: conn} do
    body = conn |> post(~p"/plugs/fridge/switch_rules", @valid) |> stream_response(200)

    assert [rule] = Repo.all(Rule)

    assert {rule.plug_id, rule.action, rule.at_minute, rule.days, rule.enabled, rule.group_id} ==
             {"fridge", "off", 1320, [1, 2], true, nil}

    assert body =~ "sw_count_fridge"
    assert body =~ "Schaltzeiten (1)"
  end

  test "create rejects a direction that is neither on nor off", %{conn: conn} do
    body =
      conn
      |> post(~p"/plugs/fridge/switch_rules", params("22:00", "toggle", ["1"]))
      |> stream_response(422)

    assert body =~ "Richtung muss an oder aus sein"
    assert Repo.aggregate(Rule, :count) == 0
  end

  test "create with no days re-renders the form with errors and 422", %{conn: conn} do
    body =
      conn
      |> post(~p"/plugs/fridge/switch_rules", params("22:00", "off", [""]))
      |> stream_response(422)

    assert body =~ "Wochentag"
  end

  test "create for unknown plug returns 404, for non-switchable 422", %{conn: conn} do
    assert conn |> post(~p"/plugs/nope/switch_rules", @valid) |> response(404)
    assert conn |> post(~p"/plugs/bkw/switch_rules", @valid) |> response(422)
  end

  test "edit renders the form into the row of the rule", %{conn: conn} do
    rule = a_single()
    body = conn |> get(~p"/plugs/fridge/switch_rules/#{rule.id}/edit") |> stream_response(200)

    assert streams(body) == [{"replace", "sw_entry_fridge_#{rule.id}"}]
    assert body =~ "22:00"
  end

  test "update changes the rule in place and leaves a paused rule paused", %{conn: conn} do
    rule = a_single()
    Rules.set_enabled([rule], false)

    conn
    |> patch(~p"/plugs/fridge/switch_rules/#{rule.id}", params("07:30", "on", ["", "6", "7"]))
    |> stream_response(200)

    updated = reload(rule)

    assert {updated.action, updated.at_minute, updated.days, updated.enabled} ==
             {"on", 450, [6, 7], false}

    assert Repo.aggregate(Rule, :count) == 1
  end

  test "failed update re-renders the form into the same row and 422", %{conn: conn} do
    rule = a_single()

    body =
      conn
      |> patch(~p"/plugs/fridge/switch_rules/#{rule.id}", params("99:99", "off", ["1"]))
      |> stream_response(422)

    assert streams(body) == [{"replace", "sw_entry_fridge_#{rule.id}"}]
    assert reload(rule).at_minute == 1320
  end

  test "the member route pauses and resumes the rule", %{conn: conn} do
    rule = a_single()

    conn
    |> patch(~p"/plugs/fridge/switch_rules/#{rule.id}/enabled", %{"enabled" => "false"})
    |> stream_response(200)

    refute reload(rule).enabled

    conn
    |> patch(~p"/plugs/fridge/switch_rules/#{rule.id}/enabled", %{"enabled" => "true"})
    |> stream_response(200)

    assert reload(rule).enabled
  end

  test "destroy removes the rule", %{conn: conn} do
    rule = a_single()

    assert conn |> delete(~p"/plugs/fridge/switch_rules/#{rule.id}") |> stream_response(200) =~
             "sw_rules_fridge"

    assert Repo.aggregate(Rule, :count) == 0
  end

  test "a rule that is not on this plug is not found", %{conn: conn} do
    rule = a_single()
    Repo.update_all(Rule, set: [plug_id: "gone"])

    assert conn |> get(~p"/plugs/fridge/switch_rules/#{rule.id}/edit") |> response(404)
    assert conn |> patch(~p"/plugs/fridge/switch_rules/#{rule.id}", @valid) |> response(404)

    assert conn
           |> patch(~p"/plugs/fridge/switch_rules/#{rule.id}/enabled", %{"enabled" => "false"})
           |> response(404)

    assert conn |> delete(~p"/plugs/fridge/switch_rules/#{rule.id}") |> response(404)
  end

  test "one half of an intact Zeitfenster is not addressable as an Einzelschaltung", %{conn: conn} do
    a_window()
    half = Repo.one(from r in Rule, where: r.action == "off")

    assert conn |> get(~p"/plugs/fridge/switch_rules/#{half.id}/edit") |> response(404)
    assert conn |> patch(~p"/plugs/fridge/switch_rules/#{half.id}", @valid) |> response(404)

    assert conn
           |> patch(~p"/plugs/fridge/switch_rules/#{half.id}/enabled", %{"enabled" => "false"})
           |> response(404)

    assert reload(half).enabled
    assert conn |> delete(~p"/plugs/fridge/switch_rules/#{half.id}") |> response(404)
    assert Repo.aggregate(Rule, :count) == 2
  end

  test "the half of a group left over is editable as an Einzelschaltung", %{conn: conn} do
    group_id = a_window()
    Repo.delete_all(from r in Rule, where: r.group_id == ^group_id and r.action == "on")
    orphan = Repo.one(Rule)

    assert conn |> get(~p"/plugs/fridge/switch_rules/#{orphan.id}/edit") |> stream_response(200)
    assert conn |> delete(~p"/plugs/fridge/switch_rules/#{orphan.id}") |> stream_response(200)
    assert Repo.aggregate(Rule, :count) == 0
  end

  test "every write answers 421 and writes nothing while Rails owns the schedule", %{conn: conn} do
    rule = a_single(action: "on", at: "18:00")
    Ownership.override(%{switch_schedule: :rails})
    single = params("20:00", "off", ["", "2"])

    assert conn |> post(~p"/plugs/fridge/switch_rules", single) |> response(421)
    assert conn |> patch(~p"/plugs/fridge/switch_rules/#{rule.id}", single) |> response(421)

    assert conn
           |> patch(~p"/plugs/fridge/switch_rules/#{rule.id}/enabled", %{"enabled" => "0"})
           |> response(421)

    assert conn |> delete(~p"/plugs/fridge/switch_rules/#{rule.id}") |> response(421)
    assert [%{enabled: true, at_minute: 1080}] = Repo.all(Rule)
  end
end
