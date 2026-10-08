defmodule Ziwoas.SwitchingTest do
  use Ziwoas.DataCase

  import Ecto.Query

  alias Ziwoas.{Repo, TestClock}
  alias Ziwoas.Switching
  alias Ziwoas.Switching.{Rule, Window}

  setup do
    TestClock.freeze("2026-06-15T17:00:00+02:00")
    :ok
  end

  defp valid, do: %{plug_id: "fridge", action: :off, at_minute: 1320, days: [1, 2, 3, 4, 5]}
  defp valid?(attrs), do: Rule.changeset(%Rule{}, Map.merge(valid(), attrs)).valid?

  defp save(opts \\ []) do
    attrs = %{
      on_at_time: Keyword.get(opts, :on, "10:00"),
      off_at_time: Keyword.get(opts, :off, "20:00"),
      days: Keyword.get(opts, :days, [1, 2, 3, 4, 5])
    }

    {:ok, group_id} = Switching.save_window("fridge", attrs, opts[:group_id])
    group_id
  end

  defp single!(attrs \\ %{}) do
    {:ok, rule} =
      Switching.save_single(
        "fridge",
        Map.merge(%{"at_minute_time" => "22:00", "action" => "off", "days" => ["1"]}, attrs)
      )

    rule
  end

  defp rules_of(group_id),
    do: Repo.all(from r in Rule, where: r.group_id == ^group_id, order_by: r.action)

  defp messages(changeset, field),
    do: for({^field, {message, _}} <- changeset.errors, do: message)

  describe "Rule" do
    test "validates plug, direction, minute of the day and weekdays" do
      assert valid?(%{})
      refute valid?(%{plug_id: ""})
      assert valid?(%{action: :on})
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
      assert Rule.minutes_from("08:09") == 489
      assert Rule.at_minute_time(489) == "08:09"
      assert Rule.minutes_from("") == nil
      assert Rule.minutes_from(["18:00"]) == nil
      assert Rule.at_minute_time(nil) == nil
      assert Rule.minutes_from("24:00") == nil
      assert Rule.minutes_from("23:60") == nil
    end

    test "a group holds at most one rule per direction" do
      group = Ecto.UUID.generate()
      rule = %Rule{plug_id: "fridge", action: :on, at_minute: 1, days: [1], group_id: group}
      Repo.insert!(rule)

      assert_raise Ecto.ConstraintError, fn -> Repo.insert!(%{rule | at_minute: 2}) end
    end
  end

  describe "the Zeitfenster form" do
    defp window(attrs), do: Switching.change_window(%Window{}, attrs)

    test "takes two times and the weekdays, dropping the checkboxes' blank value" do
      changeset =
        window(%{"on_at_time" => "18:00", "off_at_time" => "23:00", "days" => ["", "2", "1"]})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :days) == [1, 2]
    end

    test "refuses missing or malformed times with a German message" do
      changeset = window(%{"on_at_time" => "", "off_at_time" => "25:00", "days" => ["1"]})

      assert messages(changeset, :on_at_time) == ["Uhrzeit im Format HH:MM angeben"]
      assert messages(changeset, :off_at_time) == ["Uhrzeit im Format HH:MM angeben"]
    end

    test "refuses two equal times" do
      changeset = window(%{"on_at_time" => "18:00", "off_at_time" => "18:00", "days" => ["1"]})
      assert messages(changeset, :off_at_time) == ["An- und Aus-Zeit müssen sich unterscheiden"]
    end

    test "needs at least one weekday, and only real ones" do
      for days <- [[""], [], ["0"], ["8"]] do
        changeset = window(%{"on_at_time" => "18:00", "off_at_time" => "19:00", "days" => days})
        assert messages(changeset, :days) == ["mindestens ein Wochentag muss gewählt sein"]
      end
    end

    test "a time that is not a string does not cast" do
      changeset = window(%{"on_at_time" => ["18:00"], "off_at_time" => "19:00", "days" => ["1"]})
      refute changeset.valid?
      assert [{"is invalid", _}] = Keyword.get_values(changeset.errors, :on_at_time)
    end

    test "a stored window reads back the days that were typed" do
      group_id = save(on: "22:00", off: "06:00")

      assert %Window{on_at_time: "22:00", off_at_time: "06:00", days: [1, 2, 3, 4, 5]} =
               Switching.window("fridge", group_id)

      assert Switching.window("other", group_id) == nil
    end
  end

  describe "save_window" do
    test "writes exactly two rules of one group, one per direction" do
      group_id = save()
      [off, on] = rules_of(group_id)

      assert {on.plug_id, on.action, on.at_minute, on.days, on.enabled} ==
               {"fridge", :on, 600, [1, 2, 3, 4, 5], true}

      assert {off.plug_id, off.action, off.at_minute, off.days, off.enabled} ==
               {"fridge", :off, 1200, [1, 2, 3, 4, 5], true}
    end

    test "two windows get two groups" do
      refute save() == save(on: "06:00", off: "08:00")
      assert Repo.aggregate(from(r in Rule, where: r.action == :on), :count) == 2
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
      Switching.set_enabled(rules_of(group_id), false)

      save(on: "11:00", off: "21:00", days: [6], group_id: group_id)

      [off, on] = rules_of(group_id)
      assert Enum.map(rules_of(group_id), & &1.id) == before
      assert {on.at_minute, on.days, off.at_minute, off.days} == {660, [6], 1260, [6]}
      assert {on.enabled, off.enabled} == {false, false}
      assert Repo.aggregate(Rule, :count) == 2
    end

    test "a refused window writes nothing and answers the changeset" do
      assert {:error, changeset} =
               Switching.save_window("fridge", %{
                 on_at_time: "10:00",
                 off_at_time: "24:00",
                 days: [1]
               })

      assert changeset.action == :insert
      assert messages(changeset, :off_at_time) == ["Uhrzeit im Format HH:MM angeben"]
      assert Repo.aggregate(Rule, :count) == 0
    end
  end

  describe "save_single" do
    test "writes one rule without a group" do
      rule = single!(%{"days" => ["", "2", "1"]})

      assert {rule.plug_id, rule.action, rule.at_minute, rule.days, rule.enabled, rule.group_id} ==
               {"fridge", :off, 1320, [1, 2], true, nil}
    end

    test "updates in place and leaves a paused rule paused" do
      rule = single!()
      Switching.set_enabled([rule], false)

      {:ok, updated} =
        Switching.save_single(
          "fridge",
          %{"at_minute_time" => "07:30", "action" => "on", "days" => ["6", "7"]},
          Repo.get!(Rule, rule.id)
        )

      assert {updated.id, updated.action, updated.at_minute, updated.days} ==
               {rule.id, :on, 450, [6, 7]}

      refute Repo.get!(Rule, rule.id).enabled
    end

    test "refuses a direction that is neither on nor off, a bad time and no days" do
      assert {:error, changeset} =
               Switching.save_single("fridge", %{
                 "at_minute_time" => "99:99",
                 "action" => "toggle",
                 "days" => [""]
               })

      assert messages(changeset, :action) == ["Richtung muss an oder aus sein"]
      assert messages(changeset, :at_minute_time) == ["Uhrzeit im Format HH:MM angeben"]
      assert messages(changeset, :days) == ["mindestens ein Wochentag muss gewählt sein"]
      assert Repo.aggregate(Rule, :count) == 0
    end

    test "a new form switches off and shows a stored rule's time" do
      assert Ecto.Changeset.get_field(Switching.change_single(), :action) == :off

      rule = single!(%{"at_minute_time" => "06:05"})
      assert Ecto.Changeset.get_field(Switching.change_single(rule), :at_minute_time) == "06:05"
    end
  end

  describe "lookups and writes" do
    test "one half of an intact Zeitfenster is no Einzelschaltung, a leftover half is" do
      group_id = save()
      [off, on] = rules_of(group_id)

      assert Switching.single("fridge", to_string(off.id)) == nil
      Switching.delete_rules([on])
      assert %Rule{id: id} = Switching.single("fridge", to_string(off.id))
      assert id == off.id
      assert Switching.single("other", to_string(off.id)) == nil
      assert Switching.single("fridge", "abc") == nil
      assert Switching.single("fridge", "#{off.id}x") == nil
      assert Switching.window("fridge", group_id) == nil
    end

    test "pausing and resuming moves every given rule" do
      rules = rules_of(save())
      assert Switching.set_enabled(rules, false) == :ok
      assert Enum.map(Repo.all(Rule), & &1.enabled) == [false, false]

      Switching.set_enabled(rules, true)
      assert Enum.map(Repo.all(Rule), & &1.enabled) == [true, true]
    end

    test "delete removes only the given rules" do
      keep = single!()
      rules_of(save()) |> Switching.delete_rules()
      assert Repo.all(from r in Rule, select: r.id) == [keep.id]
    end
  end
end
