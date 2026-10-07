defmodule Ziwoas.Switching.RowTest do
  # Mirrors test/models/switching/row_test.rb.
  use Ziwoas.DataCase

  alias Ziwoas.{Clock, Repo}
  alias Ziwoas.Plugs.{Plug, State}
  alias Ziwoas.Switching.{Command, Row, Rule}

  @zone "Europe/Berlin"
  @plug %Plug{id: "fridge", name: "Kühlschrank", role: :consumer, switchable: true}

  # Monday 2026-06-15.
  defp at(hour, minute \\ 0),
    do:
      DateTime.new!(~D[2026-06-15], Time.new!(hour, minute, 0), @zone)
      |> usec()

  defp window(opts \\ []) do
    group = Ecto.UUID.generate()

    for {action, minute} <- [
          {"on", Keyword.get(opts, :on_at, 1080)},
          {"off", Keyword.get(opts, :off_at, 1380)}
        ] do
      Repo.insert!(%Rule{
        plug_id: Keyword.get(opts, :plug_id, "fridge"),
        action: action,
        at_minute: minute,
        days: [1],
        enabled: Keyword.get(opts, :enabled, true),
        group_id: group
      })
    end
  end

  defp build(now), do: Row.build(@plug, now, @zone)

  test "build collects state, last command, entries, watt and next edge" do
    now = at(17)
    Repo.insert!(%State{plug_id: "fridge", output: true, updated_at: now, inserted_at: now})

    Repo.insert!(%Command{
      plug_id: "fridge",
      action: "on",
      source: "schedule",
      inserted_at: now,
      updated_at: now
    })

    window()
    insert_sample!("fridge", DateTime.to_unix(now) - 30, 42, 1)

    row = build(now)
    assert Row.on?(row)
    refute Row.offline?(row)
    assert row.watt == 42.0
    assert length(row.entries) == 1
    assert row.next_edge.action == :on
    assert DateTime.compare(row.next_edge.at, at(18)) == :eq
    assert row.last_command.action == "on"
  end

  test "offline when the last sample outlives the deadline, or is missing" do
    now = at(17)
    assert Row.offline?(build(now))
    insert_sample!("fridge", DateTime.to_unix(now) - 130, 1, 1)
    assert Row.offline?(build(now))
    insert_sample!("fridge", DateTime.to_unix(now) - 60, 1, 1)
    refute Row.offline?(build(now))
  end

  test "on? falls back to the last command without plug state, default off" do
    refute Row.on?(build(at(17)))

    Repo.insert!(%Command{
      plug_id: "fridge",
      action: "on",
      source: "manual",
      inserted_at: at(17),
      updated_at: at(17)
    })

    assert Row.on?(build(at(17)))
  end

  test "on? lets a manual command fresher than the plug state win, until the device confirms" do
    state =
      Repo.insert!(%State{
        plug_id: "fridge",
        output: false,
        inserted_at: at(17),
        updated_at: at(17)
      })

    Repo.insert!(%Command{
      plug_id: "fridge",
      action: "on",
      source: "manual",
      inserted_at: at(17, 5),
      updated_at: at(17, 5)
    })

    assert Row.on?(build(at(17, 5)))

    Repo.update!(Ecto.Changeset.change(state, updated_at: at(17, 6)))
    refute Row.on?(build(at(17, 6)))
  end

  test "paused rules do not produce a next edge but stay listed" do
    window(enabled: false)
    row = build(at(17))
    assert row.next_edge == nil
    assert length(row.entries) == 1
  end

  test "adjoining windows announce the on edge, like the tick performs it" do
    window(on_at: 360, off_at: 600)
    window(on_at: 600, off_at: 840)
    row = build(at(9))
    assert row.next_edge.action == :on
    assert DateTime.compare(row.next_edge.at, at(10)) == :eq
  end

  test "entries of one plug are folded and sorted, other plugs stay out" do
    late = Repo.insert!(%Rule{plug_id: "fridge", action: "off", at_minute: 1320, days: [1]})
    [early, _] = window(on_at: 360, off_at: 600)
    window(plug_id: "other")

    assert Enum.map(build(at(17)).entries, &Ziwoas.Switching.Schedule.id/1) == [
             early.group_id,
             late.id
           ]
  end

  test "the count is Schaltzeiten, not rows" do
    window()
    Repo.insert!(%Rule{plug_id: "fridge", action: "off", at_minute: 60, days: [1]})
    assert Row.rule_count(build(Clock.now())) == 3
  end
end
