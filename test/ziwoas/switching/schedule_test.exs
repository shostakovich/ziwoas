defmodule Ziwoas.Switching.ScheduleTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Switching.{Rule, Schedule}
  alias Ziwoas.Switching.Schedule.{Single, Window}

  defp rule(overrides) do
    struct!(
      %Rule{id: 1, action: :on, at_minute: 600, days: [1], enabled: true, group_id: nil},
      overrides
    )
  end

  defp ids(entries), do: Enum.map(entries, &Schedule.id/1)

  test "two rules of one group fold into a window, in whatever order they arrive" do
    on = rule(id: 2, action: :on, at_minute: 600, group_id: "g")
    off = rule(id: 1, action: :off, at_minute: 1200, group_id: "g")

    assert [%Window{on: ^on, off: ^off} = window] = Schedule.fold([off, on])
    assert Schedule.id(window) == "g"
  end

  test "a rule without a group folds into a single, keeping its direction" do
    assert [%Single{rule: %{action: :off}} = single] =
             Schedule.fold([rule(id: 7, action: :off, at_minute: 1320)])

    assert Schedule.id(single) == 7
  end

  test "groups are folded independently of each other" do
    entries =
      Schedule.fold([
        rule(id: 1, action: :on, at_minute: 360, group_id: "a"),
        rule(id: 2, action: :off, at_minute: 600, group_id: "a"),
        rule(id: 3, action: :on, at_minute: 900, group_id: "b"),
        rule(id: 4, action: :off, at_minute: 1200, group_id: "b"),
        rule(id: 5, action: :off, at_minute: 1380)
      ])

    assert ids(entries) == ["a", "b", 5]
    assert Schedule.fold([]) == []
  end

  test "an entry carries the weekdays, time and pause state of its on rule" do
    [window] =
      Schedule.fold([
        rule(
          id: 1,
          action: :on,
          at_minute: 1320,
          days: [1, 2, 3, 4, 5],
          enabled: false,
          group_id: "g"
        ),
        rule(
          id: 2,
          action: :off,
          at_minute: 360,
          days: [2, 3, 4, 5, 6],
          enabled: false,
          group_id: "g"
        )
      ])

    assert {Schedule.days(window), Schedule.at_minute(window), Schedule.enabled?(window)} ==
             {[1, 2, 3, 4, 5], 1320, false}

    [single] = Schedule.fold([rule(id: 1, at_minute: 1320, days: [6, 7], enabled: false)])

    assert {Schedule.days(single), Schedule.at_minute(single), Schedule.enabled?(single)} ==
             {[6, 7], 1320, false}
  end

  test "entries sort by their earliest time, a window by its on time" do
    entries =
      Schedule.fold([
        rule(id: 1, at_minute: 1320),
        rule(id: 2, action: :on, at_minute: 600, group_id: "g"),
        rule(id: 3, action: :off, at_minute: 1200, group_id: "g"),
        rule(id: 4, at_minute: 300)
      ])

    assert ids(entries) == [4, "g", 1]

    crosser =
      Schedule.fold([
        rule(id: 1, action: :on, at_minute: 1320, group_id: "g"),
        rule(id: 2, action: :off, at_minute: 360, group_id: "g"),
        rule(id: 3, at_minute: 600)
      ])

    assert ids(crosser) == [3, "g"]
  end

  test "entries at the same time sort by their smallest rule id" do
    entries =
      Schedule.fold([
        rule(id: 5, at_minute: 600),
        rule(id: 3, action: :on, at_minute: 600, group_id: "g"),
        rule(id: 9, action: :off, at_minute: 900, group_id: "g"),
        rule(id: 4, at_minute: 600)
      ])

    assert ids(entries) == ["g", 4, 5]
  end

  test "a group that is not a pair folds into singles" do
    assert [%Single{}] = Schedule.fold([rule(id: 1, action: :on, group_id: "lonely")])

    twice =
      Schedule.fold([
        rule(id: 1, action: :on, at_minute: 600, group_id: "twice"),
        rule(id: 2, action: :on, at_minute: 900, group_id: "twice")
      ])

    assert ids(twice) == [1, 2]
    assert Enum.all?(twice, &match?(%Single{}, &1))
  end
end
