defmodule ZiwoasWeb.SwitchesComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

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

  defp classes(doc, selector),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute("class") |> hd() |> String.split()

  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  test "a Zeitfenster is one filled pill in a row named by its group" do
    doc = entry(window())

    assert Enum.count(LazyHTML.query(doc, "div#sw_entry_fridge_g-1")) == 1
    refute "border" in classes(doc, "span.badge")
    assert Enum.empty?(LazyHTML.query(doc, "span.badge .fw-bold"))
    assert squish(LazyHTML.text(LazyHTML.query(doc, "span.badge"))) == "Mo–Fr · 10:00–20:00"
  end

  test "an Einzelschaltung is an open, directed pill in a row named by its rule" do
    doc = entry(single())

    assert Enum.count(LazyHTML.query(doc, "div#sw_entry_fridge_7")) == 1
    assert LazyHTML.text(LazyHTML.query(doc, "span.badge.border .fw-bold")) == "→ aus"
    assert squish(LazyHTML.text(LazyHTML.query(doc, "span.badge"))) == "täglich · 22:00 → aus"
    assert LazyHTML.text(LazyHTML.query(entry(single(:on)), "span.badge .fw-bold")) == "→ an"
  end

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  test "the buttons address the group or the rule and name what they act on" do
    window = entry(window())
    addressed = "[phx-value-plug_id=fridge][phx-value-kind=window][phx-value-id=g-1]"

    assert count(window, "button[phx-click=set_enabled][phx-value-enabled=false]#{addressed}") ==
             1

    assert count(window, "button[phx-click=edit_entry]#{addressed}") == 1
    assert count(window, "button[phx-click=delete_entry]#{addressed}") == 1

    assert LazyHTML.attribute(LazyHTML.query(window, "[aria-label]"), "aria-label") ==
             ["Zeitfenster pausieren", "Zeitfenster bearbeiten", "Zeitfenster löschen"]

    single = entry(single())

    assert count(single, "button[phx-click=set_enabled][phx-value-kind=rule][phx-value-id='7']") ==
             1

    assert LazyHTML.attribute(LazyHTML.query(single, "[aria-label]"), "aria-label") ==
             ["Schaltzeit pausieren", "Schaltzeit bearbeiten", "Schaltzeit löschen"]
  end

  test "deleting asks first" do
    assert LazyHTML.attribute(
             LazyHTML.query(entry(window()), "button[phx-click=delete_entry]"),
             "data-confirm"
           ) == ["Zeitfenster wirklich löschen?"]

    assert LazyHTML.attribute(
             LazyHTML.query(entry(single()), "button[phx-click=delete_entry]"),
             "data-confirm"
           ) == ["Schaltzeit wirklich löschen?"]
  end

  test "a paused row is struck through, colourless, and its button resumes" do
    doc = entry(window(false))

    assert "text-decoration-line-through" in classes(doc, "span.badge")
    assert Enum.filter(classes(doc, "span.badge"), &String.contains?(&1, "primary")) == []

    assert hd(LazyHTML.attribute(LazyHTML.query(doc, "button[aria-label]"), "aria-label")) ==
             "Zeitfenster aktivieren"

    assert count(doc, "button[phx-click=set_enabled][phx-value-enabled=true]") == 1

    assert LazyHTML.attribute(LazyHTML.query(doc, "[phx-click=set_enabled] svg"), "data-icon") ==
             ["play"]
  end

  test "a running pill is primary: filled for a Zeitfenster, outlined for an Einzelschaltung" do
    filled = classes(entry(window()), "span.badge")
    outlined = classes(entry(single()), "span.badge")

    assert "bg-primary-subtle" in filled and "text-primary-emphasis" in filled
    refute "border-primary" in filled
    assert "border-primary" in outlined and "text-primary-emphasis" in outlined
    refute "bg-primary-subtle" in outlined

    assert LazyHTML.attribute(LazyHTML.query(entry(single()), ".btn.btn-icon svg"), "data-icon") ==
             ~w[pause edit delete]
  end

  describe "helpers" do
    defp at(hour, minute), do: DateTime.new!(~D[2026-06-15], Time.new!(hour, minute, 0), @zone)

    defp row(opts) do
      now = at(19, 0)
      seen = Keyword.get(opts, :last_seen, DateTime.add(now, -60))

      %Row{
        plug: @plug,
        entries: [],
        state: %State{plug_id: "fridge", output: Keyword.get(opts, :on, true), updated_at: now},
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

    defp line(row), do: SwitchesComponents.status_line(row, @zone)

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
               "An seit 18:00 (Zeitplan) · nächste Schaltung: 23:00 → aus"

      assert line(row(on: false, edge: edge(:on, 6, 30))) == "Aus · nächste Schaltung: 06:30 → an"
      assert line(row(on: false, command: command(:on, :manual))) == "Aus · kein Zeitplan"

      assert line(row(on: true, command: %{command(:off, :manual) | inserted_at: at(17, 0)})) ==
               "An · kein Zeitplan"
    end

    test "an offline plug counts whole minutes of silence" do
      assert line(row(last_seen: at(17, 30))) == "Keine Statusmeldung seit 90 min"
      assert line(row(last_seen: at(18, 35))) == "Keine Statusmeldung seit 25 min"
      assert line(row(last_seen: nil)) == "Noch keine Statusmeldung"
    end
  end
end
