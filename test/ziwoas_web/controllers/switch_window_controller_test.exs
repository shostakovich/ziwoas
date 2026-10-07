defmodule ZiwoasWeb.SwitchWindowControllerTest do
  # Mirrors test/controllers/switch_windows_controller_test.rb.
  use ZiwoasWeb.ConnCase

  import Ecto.Query
  import ZiwoasWeb.TurboCase

  alias Ziwoas.{Repo, TestClock}
  alias Ziwoas.Switching.{Rule, Rules}

  setup %{conn: conn} do
    TestClock.freeze("2026-06-15T17:00:00+02:00")
    {:ok, conn: turbo(conn)}
  end

  @valid %{
    "switch_window" => %{
      "on_at_time" => "18:00",
      "off_at_time" => "23:00",
      "days" => ["", "1", "2"]
    }
  }

  defp a_window(opts \\ []) do
    Rules.save_window("fridge", %{
      on_at_time: Keyword.get(opts, :on, "18:00"),
      off_at_time: Keyword.get(opts, :off, "23:00"),
      days: Keyword.get(opts, :days, [1, 2, 3, 4, 5])
    })
  end

  defp rules_of(group_id),
    do: Repo.all(from r in Rule, where: r.group_id == ^group_id, order_by: r.action)

  defp params(on, off, days),
    do: %{"switch_window" => %{"on_at_time" => on, "off_at_time" => off, "days" => days}}

  test "new renders the inline editor: two times, the weekdays as toggle buttons", %{conn: conn} do
    body = conn |> get(~p"/plugs/fridge/switch_windows/new") |> stream_response(200)
    doc = stream_doc(body)

    assert streams(body) == [{"update", "sw_editor_fridge"}]
    assert count(doc, "input.form-control[type=time]") == 2

    assert count(
             doc,
             "[role=group][aria-label=Wochentage] input.btn-check[type=checkbox][name='switch_window[days][]']"
           ) == 7

    assert count(doc, "input[type=hidden][name='switch_window[days][]'][value='']") == 1
  end

  test "create writes both halves as one group and re-renders the rules region", %{conn: conn} do
    body = conn |> post(~p"/plugs/fridge/switch_windows", @valid) |> stream_response(200)

    [off, on] = Repo.all(from r in Rule, order_by: r.action)
    assert {on.plug_id, on.at_minute, on.days} == {"fridge", 1080, [1, 2]}
    assert {off.plug_id, off.at_minute, off.days} == {"fridge", 1380, [1, 2]}
    assert on.group_id == off.group_id

    assert streams(body) == [
             {"replace", "sw_rules_fridge"},
             {"replace", "sw_count_fridge"},
             {"replace", "sw_head_fridge"}
           ]
  end

  test "create with no days re-renders the form with errors and 422", %{conn: conn} do
    body =
      conn
      |> post(~p"/plugs/fridge/switch_windows", params("18:00", "23:00", [""]))
      |> stream_response(422)

    assert body =~ "mindestens ein Wochentag muss gewählt sein"
    assert streams(body) == [{"update", "sw_editor_fridge"}]
    assert Repo.aggregate(Rule, :count) == 0
  end

  test "create with two identical times is rejected", %{conn: conn} do
    body =
      conn
      |> post(~p"/plugs/fridge/switch_windows", params("18:00", "18:00", ["1"]))
      |> stream_response(422)

    assert body =~ "An- und Aus-Zeit müssen sich unterscheiden"
    assert Repo.aggregate(Rule, :count) == 0
  end

  test "a refused form keeps what could be read, and its messages once", %{conn: conn} do
    body =
      conn
      |> post(~p"/plugs/fridge/switch_windows", params("", "25:00", ["x", "1"]))
      |> stream_response(422)

    doc = stream_doc(body)

    assert LazyHTML.text(LazyHTML.query(doc, ".text-danger-emphasis")) =~
             "must be an integer, Uhrzeit im Format HH:MM angeben"

    assert doc |> LazyHTML.query("#switch_window_off_at_time") |> LazyHTML.attribute("value") == [
             "25:00"
           ]

    assert doc |> LazyHTML.query("#switch_window_on_at_time") |> LazyHTML.attribute("value") == []
    assert doc |> LazyHTML.query("input[checked]") |> LazyHTML.attribute("value") == ["1"]
  end

  test "a time that is not a string is refused without echoing it", %{conn: conn} do
    body =
      conn
      |> post(~p"/plugs/fridge/switch_windows", params(["18:00"], "19:00", ["2"]))
      |> stream_response(422)

    assert body =~ "must be a string"

    assert stream_doc(body)
           |> LazyHTML.query("#switch_window_on_at_time")
           |> LazyHTML.attribute("value") == []
  end

  test "create for unknown plug returns 404, for non-switchable 422", %{conn: conn} do
    assert conn |> post(~p"/plugs/nope/switch_windows", @valid) |> response(404)
    assert conn |> post(~p"/plugs/bkw/switch_windows", @valid) |> response(422)
  end

  test "edit renders the form into the row of the group", %{conn: conn} do
    group_id = a_window()
    body = conn |> get(~p"/plugs/fridge/switch_windows/#{group_id}/edit") |> stream_response(200)

    assert streams(body) == [{"replace", "sw_entry_fridge_#{group_id}"}]
    assert body =~ "18:00"
    assert body =~ "23:00"
  end

  test "edit shows a window past midnight with the times and days that were typed", %{conn: conn} do
    group_id = a_window(on: "22:00", off: "06:00")
    assert [%{days: [2, 3, 4, 5, 6]}, _on] = rules_of(group_id)

    doc =
      conn
      |> get(~p"/plugs/fridge/switch_windows/#{group_id}/edit")
      |> stream_response(200)
      |> stream_doc()

    assert doc |> LazyHTML.query("input[checked]") |> LazyHTML.attribute("value") == ~w[1 2 3 4 5]
  end

  test "update moves both halves in place, keeping the rule ids", %{conn: conn} do
    group_id = a_window()
    before = Enum.map(rules_of(group_id), & &1.id)

    conn
    |> patch(~p"/plugs/fridge/switch_windows/#{group_id}", params("09:00", "17:00", ["", "6"]))
    |> stream_response(200)

    assert Enum.map(rules_of(group_id), & &1.id) == before
    assert Enum.map(rules_of(group_id), &{&1.at_minute, &1.days}) == [{1020, [6]}, {540, [6]}]
  end

  test "failed update re-renders the form into the same row and 422", %{conn: conn} do
    group_id = a_window()

    body =
      conn
      |> patch(~p"/plugs/fridge/switch_windows/#{group_id}", params("", "23:00", ["1"]))
      |> stream_response(422)

    assert streams(body) == [{"replace", "sw_entry_fridge_#{group_id}"}]
    assert Enum.map(rules_of(group_id), & &1.at_minute) |> Enum.sort() == [1080, 1380]
  end

  test "the member route pauses and resumes both halves at once", %{conn: conn} do
    group_id = a_window()

    conn
    |> patch(~p"/plugs/fridge/switch_windows/#{group_id}/enabled", %{"enabled" => "false"})
    |> stream_response(200)

    assert Enum.map(rules_of(group_id), & &1.enabled) == [false, false]

    conn
    |> patch(~p"/plugs/fridge/switch_windows/#{group_id}/enabled", %{"enabled" => "true"})
    |> stream_response(200)

    assert Enum.map(rules_of(group_id), & &1.enabled) == [true, true]
  end

  test "destroy removes both halves", %{conn: conn} do
    group_id = a_window()
    body = conn |> delete(~p"/plugs/fridge/switch_windows/#{group_id}") |> stream_response(200)

    assert body =~ "sw_rules_fridge"
    assert Repo.aggregate(Rule, :count) == 0
  end

  test "a group that is not on this plug is not found", %{conn: conn} do
    group_id = a_window()
    Repo.update_all(Rule, set: [plug_id: "gone"])

    assert conn |> get(~p"/plugs/fridge/switch_windows/#{group_id}/edit") |> response(404)
    assert conn |> patch(~p"/plugs/fridge/switch_windows/#{group_id}", @valid) |> response(404)

    assert conn
           |> patch(~p"/plugs/fridge/switch_windows/#{group_id}/enabled", %{"enabled" => "false"})
           |> response(404)

    assert conn |> delete(~p"/plugs/fridge/switch_windows/#{group_id}") |> response(404)
  end

  test "a group missing its off half is not editable as a window", %{conn: conn} do
    group_id = a_window()
    Repo.delete_all(from r in Rule, where: r.action == "off")

    assert conn |> get(~p"/plugs/fridge/switch_windows/#{group_id}/edit") |> response(404)
  end
end
