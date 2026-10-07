defmodule Ziwoas.Switching.RulesTest do
  # Mirrors test/models/switching/rule_test.rb and rules/save_window_test.rb.
  use Ziwoas.DataCase, async: true

  import Ecto.Query

  alias Ziwoas.{Clock, Ownership, Repo}
  alias Ziwoas.Switching.{Rule, Rules}

  setup %{repo: repo} do
    Clock.freeze("2026-06-15T17:00:00+02:00")
    Repo.put_writer(:main, repo)
    Ownership.override(%{switch_schedule: :phoenix})
    on_exit(&Ownership.clear_override/0)
    :ok
  end

  defp valid, do: %{plug_id: "fridge", action: "off", at_minute: 1320, days: [1, 2, 3, 4, 5]}
  defp valid?(attrs), do: Rule.changeset(%Rule{}, Map.merge(valid(), attrs)).valid?

  defp save(opts \\ []) do
    attrs = %{
      on_at_time: Keyword.get(opts, :on, "10:00"),
      off_at_time: Keyword.get(opts, :off, "20:00"),
      days: Keyword.get(opts, :days, [1, 2, 3, 4, 5])
    }

    Rules.save_window("fridge", attrs, opts[:group_id])
  end

  defp rules_of(group_id),
    do: Repo.all(from r in Rule, where: r.group_id == ^group_id, order_by: r.action)

  describe "Rule" do
    test "validates plug, direction, minute of the day and weekdays" do
      assert valid?(%{})
      refute valid?(%{plug_id: ""})
      assert valid?(%{action: "on"})
      refute valid?(%{action: "toggle"})
      refute valid?(%{action: nil})
      refute valid?(%{at_minute: -1})
      refute valid?(%{at_minute: 1440})
      refute valid?(%{at_minute: nil})
      assert valid?(%{at_minute: 0}) and valid?(%{at_minute: 1439})
      refute valid?(%{days: []})
      refute valid?(%{days: [0]})
      refute valid?(%{days: [8]})
      refute valid?(%{days: nil})
    end

    test "the minute message is German" do
      changeset = Rule.changeset(%Rule{}, %{valid() | at_minute: 1440})
      assert {"muss zwischen 00:00 und 23:59 liegen", _} = changeset.errors[:at_minute]
    end

    test "days are normalised to sorted unique integers" do
      assert Ecto.Changeset.get_change(
               Rule.changeset(%Rule{}, %{valid() | days: [5, 1, 5]}),
               :days
             ) == [1, 5]
    end

    test "at_minute_time formats and parses HH:MM" do
      assert Rule.at_minute_time(1320) == "22:00"
      assert Rule.minutes_from("07:05") == 425
      assert Rule.minutes_from("18:00:00") == 1080
      # A leading zero must not be read as an octal prefix.
      assert Rule.minutes_from("08:09") == 489
      assert Rule.at_minute_time(489) == "08:09"
      assert Rule.minutes_from("") == nil
      assert Rule.at_minute_time(nil) == nil
      assert Rule.minutes_from("24:00") == nil
      assert Rule.minutes_from("23:60") == nil
    end

    test "a group holds at most one rule per direction" do
      group = Ecto.UUID.generate()

      Repo.write(:switch_schedule, fn ->
        Repo.insert!(%Rule{
          plug_id: "fridge",
          action: "on",
          at_minute: 1,
          days: [1],
          group_id: group
        })

        assert_raise Ecto.ConstraintError, fn ->
          Repo.insert!(%Rule{
            plug_id: "fridge",
            action: "on",
            at_minute: 2,
            days: [1],
            group_id: group
          })
        end
      end)
    end
  end

  describe "save_window" do
    test "writes exactly two rules of one group, one per direction" do
      group_id = save()
      [off, on] = rules_of(group_id)

      assert {on.plug_id, on.action, on.at_minute, on.days, on.enabled} ==
               {"fridge", "on", 600, [1, 2, 3, 4, 5], true}

      assert {off.plug_id, off.action, off.at_minute, off.days, off.enabled} ==
               {"fridge", "off", 1200, [1, 2, 3, 4, 5], true}
    end

    test "two windows get two groups" do
      refute save() == save(on: "06:00", off: "08:00")
      assert Repo.aggregate(from(r in Rule, where: r.action == "on"), :count) == 2
    end

    test "an off time before the on time shifts the off weekdays one day forward, Sunday to Monday" do
      [off, on] = rules_of(save(on: "22:00", off: "06:00"))
      assert {on.days, off.days} == {[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]}

      [wrapped, _on] = rules_of(save(on: "22:00", off: "06:00", days: [6, 7]))
      assert wrapped.days == [1, 7]
    end

    test "editing updates both rules in place, keeping ids and the pause state" do
      group_id = save()
      before = Enum.map(rules_of(group_id), & &1.id)
      Rules.set_enabled(rules_of(group_id), false)

      save(on: "11:00", off: "21:00", days: [6], group_id: group_id)

      [off, on] = rules_of(group_id)
      assert Enum.map(rules_of(group_id), & &1.id) == before
      assert {on.at_minute, on.days, off.at_minute, off.days} == {660, [6], 1260, [6]}
      assert {on.enabled, off.enabled} == {false, false}
      assert Repo.aggregate(Rule, :count) == 2
    end

    test "a rejected half rolls the whole window back" do
      assert_raise Ecto.InvalidChangesetError, fn -> save(off: "24:00") end
      assert Repo.aggregate(Rule, :count) == 0
    end
  end

  describe "lookups" do
    test "one half of an intact Zeitfenster is no Einzelschaltung, a leftover half is" do
      group_id = save()
      [off, on] = rules_of(group_id)

      assert Rules.single("fridge", to_string(off.id)) == nil
      Rules.delete([on])
      assert %Rule{id: id} = Rules.single("fridge", to_string(off.id))
      assert id == off.id
      assert Rules.single("other", to_string(off.id)) == nil
      assert Rules.single("fridge", "abc") == nil
    end

    test "pausing is ActiveModel's boolean cast" do
      assert Enum.map(["false", "0", "off", "OFF", "f"], &Rules.cast_boolean/1) ==
               List.duplicate(false, 5)

      assert Enum.map(["true", "1", "yes", "on"], &Rules.cast_boolean/1) ==
               List.duplicate(true, 4)

      assert Rules.cast_boolean("") == nil
      assert Rules.cast_boolean(nil) == nil
    end
  end
end
