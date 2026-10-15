defmodule ZiwoasWeb.SwitchesComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Setzkasten.Components.Data
  alias Ziwoas.Plugs.{Plug, State}
  alias Ziwoas.Switching.{Command, Row, Rule}
  alias Ziwoas.Switching.Edges.Edge
  alias Ziwoas.Switching.Schedule.{Single, Window}
  alias ZiwoasWeb.SwitchesComponents

  @plug %Plug{id: "fridge", name: "Kühlschrank", role: :consumer, switchable: true}
  @zone "Europe/Berlin"

  defp rule(opts) do
    struct!(%Rule{plug_id: "fridge", days: [1, 2, 3, 4, 5], enabled: true, group_id: nil}, opts)
  end

  defp window(enabled \\ true) do
    %Window{
      on: rule(id: 1, action: :on, at_minute: 600, enabled: enabled, group_id: "g-1"),
      off: rule(id: 2, action: :off, at_minute: 1200, enabled: enabled, group_id: "g-1")
    }
  end

  defp single(action \\ :off, enabled \\ true),
    do: %Single{
      rule:
        rule(id: 7, action: action, at_minute: 1320, days: Enum.to_list(1..7), enabled: enabled)
    }

  defp entry(entry),
    do:
      render_component(&SwitchesComponents.schedule_entry/1, entry: entry, plug: @plug)
      |> LazyHTML.from_fragment()

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp text(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.text() |> plain()

  defp plain(text), do: text |> String.replace(["⁠", " "], " ") |> squish()
  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  defp label(doc, id), do: doc |> LazyHTML.query("##{id}") |> LazyHTML.attribute("aria-label")

  defp pushed(doc, id) do
    [json] = doc |> LazyHTML.query("##{id}") |> LazyHTML.attribute("phx-click")
    [["push", %{"event" => event, "value" => value}]] = Jason.decode!(json)
    {event, value}
  end

  test "a Zeitfenster is a row named by its group, with days and both times" do
    doc = entry(window())

    assert count(doc, "li#sw_entry_fridge_g-1[data-enabled=true]") == 1
    assert text(doc, "li > .list-col-grow > p.font-medium") == "Mo–Fr · 10:00–20:00"
    assert text(doc, "li > .list-col-grow > p.text-sm") == "Zeitfenster"
  end

  test "an Einzelschaltung is a row named by its rule that says which way it switches" do
    doc = entry(single())

    assert count(doc, "li#sw_entry_fridge_7") == 1
    assert text(doc, "li > .list-col-grow > p.font-medium") == "täglich · 22:00"
    assert text(doc, "li > .list-col-grow > p.text-sm") == "Einzelschaltung · schaltet aus"
    assert text(entry(single(:on)), "li > .list-col-grow > p.text-sm") =~ "schaltet ein"
  end

  test "the actions address the group or the rule and name the row they act on" do
    doc = entry(window())
    addressed = %{"plug_id" => "fridge", "kind" => "window", "id" => "g-1"}

    assert pushed(doc, "sw_entry_fridge_g-1_toggle") ==
             {"set_enabled", Map.put(addressed, "enabled", "false")}

    assert pushed(doc, "sw_entry_fridge_g-1_edit") == {"edit_entry", addressed}

    assert label(doc, "sw_entry_fridge_g-1_toggle") == ["Pausieren: Mo–Fr · 10:00–20:00"]
    assert label(doc, "sw_entry_fridge_g-1_edit") == ["Bearbeiten: Mo–Fr · 10:00–20:00"]
    assert label(doc, "sw_entry_fridge_g-1_delete") == ["Löschen: Mo–Fr · 10:00–20:00"]

    assert {"set_enabled", %{"kind" => "rule", "id" => "7"}} =
             pushed(entry(single()), "sw_entry_fridge_7_toggle")
  end

  test "deleting asks in the confirmation dialog instead of sending the event" do
    [json] =
      entry(single())
      |> LazyHTML.query("#sw_entry_fridge_7_delete")
      |> LazyHTML.attribute("phx-click")

    ops = Jason.decode!(json)

    refute Enum.any?(ops, &match?(["push", _], &1))

    assert Enum.find_value(ops, fn
             ["dispatch", %{"detail" => %{"text" => texts}}] -> texts["#confirm-delete-title"]
             _op -> nil
           end) == "Schaltzeit löschen?"
  end

  test "a paused row carries a badge and its button resumes" do
    doc = entry(window(false))

    assert count(doc, "li[data-enabled=false]") == 1
    assert text(doc, ".badge") == "Pausiert"
    assert label(doc, "sw_entry_fridge_g-1_toggle") == ["Fortsetzen: Mo–Fr · 10:00–20:00"]
    assert {"set_enabled", %{"enabled" => "true"}} = pushed(doc, "sw_entry_fridge_g-1_toggle")
  end

  test "a running row has no badge" do
    assert count(entry(single()), ".badge") == 0
  end

  describe "helpers" do
    defp at(hour, minute), do: DateTime.new!(~D[2026-06-15], Time.new!(hour, minute, 0), @zone)

    defp row(opts) do
      now = Keyword.get(opts, :now, at(19, 0))
      seen = Keyword.get(opts, :last_seen, DateTime.add(now, -60))

      %Row{
        plug: @plug,
        entries: Keyword.get(opts, :entries, []),
        state: %State{
          plug_id: "fridge",
          output: Keyword.get(opts, :on, true),
          updated_at: opts[:changed]
        },
        last_command: opts[:command],
        next_edge: opts[:edge],
        watt: nil,
        last_seen_ts: seen && DateTime.to_unix(seen),
        offline: is_nil(seen) or DateTime.diff(now, seen) > 120,
        now: now
      }
    end

    defp command(action, source),
      do: %Command{plug_id: "fridge", action: action, source: source, inserted_at: at(18, 0)}

    defp edge(action, hour, minute),
      do: %Edge{plug_id: "fridge", rule_id: 1, action: action, at: at(hour, minute)}

    defp line(row), do: row |> SwitchesComponents.status_line(@zone) |> plain()

    test "weekday labels: ranges, singles and the full week" do
      assert SwitchesComponents.weekday_label([1, 2, 3, 4, 5]) == "Mo–Fr"
      assert SwitchesComponents.weekday_label([6, 7]) == "Sa–So"
      assert SwitchesComponents.weekday_label([1, 3, 5]) == "Mo, Mi, Fr"
      assert SwitchesComponents.weekday_label([5, 1, 2, 3]) == "Mo–Mi, Fr"
      assert SwitchesComponents.weekday_label(Enum.to_list(1..7)) == "täglich"
      assert SwitchesComponents.weekday_label([4]) == "Do"
    end

    test "a Zeitfenster past midnight reads back to the days that were typed" do
      window = %Window{
        on: rule(action: :on, at_minute: 1320, days: [1, 2, 3, 4, 5]),
        off: rule(action: :off, at_minute: 360, days: [2, 3, 4, 5, 6])
      }

      assert SwitchesComponents.entry_label(window) == "Mo–Fr · 22:00–06:00"
    end

    test "the status line" do
      assert line(row(command: command(:on, :schedule), edge: edge(:off, 23, 0))) ==
               "An seit 18:00 (Zeitplan) · schaltet um 23:00 aus"

      assert line(row(on: false, edge: edge(:on, 6, 30))) == "Aus · schaltet um 06:30 ein"

      assert line(row(on: false, command: command(:on, :manual), changed: at(18, 30))) ==
               "Aus seit 18:30 · kein Zeitplan"
    end

    test "the next switching time names its day when it is not today" do
      tomorrow = %{edge(:on, 6, 30) | at: DateTime.add(at(6, 30), 1, :day)}
      assert line(row(on: false, edge: tomorrow)) == "Aus · schaltet morgen um 06:30 ein"

      friday_evening = DateTime.new!(~D[2026-06-19], ~T[20:00:00], @zone)
      monday = %{edge(:on, 7, 0) | at: DateTime.new!(~D[2026-06-22], ~T[07:00:00], @zone)}

      assert line(row(on: false, now: friday_evening, last_seen: friday_evening, edge: monday)) ==
               "Aus · schaltet Montag um 07:00 ein"
    end

    test "a plug whose every entry is paused says its schedule is paused" do
      assert line(row(on: false, entries: [window(false), single(:off, false)])) ==
               "Aus · Zeitplan pausiert"
    end

    test "a state report newer than the command dates since without a source" do
      assert line(row(on: true, command: command(:on, :manual), changed: at(18, 40))) ==
               "An seit 18:40 · kein Zeitplan"
    end

    test "since names the day when it was not today" do
      yesterday = %{command(:off, :schedule) | inserted_at: DateTime.add(at(22, 0), -1, :day)}
      last_week = %{command(:off, :schedule) | inserted_at: DateTime.add(at(22, 0), -5, :day)}

      assert line(row(on: false, command: yesterday)) ==
               "Aus seit gestern 22:00 (Zeitplan) · kein Zeitplan"

      assert line(row(on: false, command: last_week)) ==
               "Aus seit 10.06. 22:00 (Zeitplan) · kein Zeitplan"
    end

    test "the status line keeps its dot at the end of a line" do
      assert SwitchesComponents.status_line(row(on: false), @zone) ==
               Data.join_meta(["Aus", "kein Zeitplan"])
    end

    test "an offline plug counts whole minutes of silence" do
      assert line(row(last_seen: at(17, 30))) == "Keine Statusmeldung seit 90 min"
      assert line(row(last_seen: at(18, 35))) == "Keine Statusmeldung seit 25 min"
      assert line(row(last_seen: nil)) == "Noch keine Statusmeldung"
    end
  end
end
