defmodule Ziwoas.Solakon.Control.TickTest do
  # The parts of test/models/solakon/control/{tick,state,load_reader,outcome}_test.rb
  # the vectors do not reach, and where a dry run reads and writes.
  use Ziwoas.DataCase, async: false

  alias Ziwoas.{Clock, Ownership, Repo}
  alias Ziwoas.Plugs.{Plug, Roster}
  alias Ziwoas.Solakon.Reading
  alias Ziwoas.Solakon.Control.{Decision, Load, LoadReader, Outcome, State, Tick}

  @moduletag :capture_log
  @now ~U[2026-10-05 10:00:00.000000Z]

  setup %{repo: repo} do
    Repo.put_writer(:main, repo)
    Clock.freeze(@now)
    on_exit(&Ownership.clear_override/0)
    :ok
  end

  defp roster, do: Roster.new([%Plug{id: "fridge", name: "Kühlschrank", role: :consumer}])

  defp reading(attrs \\ []),
    do:
      struct(
        %Reading{
          battery_soc_pct: 55,
          pv_power_w: 0.0,
          battery_power_w: 0.0,
          battery_temperature_c: 30.0
        },
        attrs
      )

  defp shadow_repo! do
    path =
      Ziwoas.RailsFixture.build!(
        Path.expand("../../../../tmp/data/control_tick_shadow.sqlite3", __DIR__),
        rows: false
      )

    shadow =
      start_supervised!({Repo, name: nil, database: path, writable: true, pool_size: 1},
        id: :shadow
      )

    previous = Repo.get_dynamic_repo()
    Repo.put_dynamic_repo(shadow)
    Repo.query!("DELETE FROM solakon_control_states")
    Repo.put_dynamic_repo(previous)
    Repo.put_writer(:shadow, shadow)
    shadow
  end

  defp in_repo(repo, fun) do
    previous = Repo.get_dynamic_repo()
    Repo.put_dynamic_repo(repo)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  describe "dry run" do
    setup do
      Ownership.override(%{solakon_monitor: :shadow, solakon_control: :dry_run})
      %{shadow: shadow_repo!()}
    end

    test "decides from the main database's samples and stores in the shadow", %{shadow: shadow} do
      insert_sample!("fridge", DateTime.to_unix(@now) - 5, 250, 1)

      outcome = Tick.run(reading(), roster(), @now)

      assert %Outcome{status: :applied, dry_run: true} = outcome
      assert outcome.decision == %Decision{state: :normal, target_w: 250, trim: false}

      assert outcome.writes == [
               {:single, 46001, 1},
               {:single, 46002, 150},
               {:multiple, 46003, [0, 250]}
             ]

      assert Repo.aggregate(State, :count) == 0
      [row] = in_repo(shadow, fn -> Repo.all(State) end)

      assert {row.decision_state, row.last_target_w, row.last_decision_at} ==
               {"normal", 250, @now}
    end

    test "follows Rails' pause switch in the main database", %{shadow: shadow} do
      Repo.insert!(%State{paused: true})

      assert %Outcome{status: :paused} = Tick.run(reading(), roster(), @now)

      assert [%State{paused: true, decision_state: nil}] =
               in_repo(shadow, fn -> Repo.all(State) end)

      Repo.update!(Ecto.Changeset.change(State.current(), paused: false))
      assert %Outcome{status: :applied} = Tick.run(reading(), roster(), @now)
      assert [%State{paused: false}] = in_repo(shadow, fn -> Repo.all(State) end)
    end

    test "its decision log line names the dry run and the writes held back" do
      outcome = Tick.run(reading(), roster(), @now)

      assert Ziwoas.Solakon.MonitorJob.log_line(outcome) ==
               "solakon_control (dry_run): state=normal target=0W load=stale floor=0W " <>
                 "soc=55% temp=30.0C pv=0.0W battery=0.0W — not sent: " <>
                 "46001=1, 46002=150, 46003=[0, 0]"
    end
  end

  describe "the stored decision" do
    test "round-trips and expires with the inverter's watchdog" do
      Ownership.override(%{solakon_monitor: :phoenix, solakon_control: :phoenix})

      state =
        Repo.write(:solakon_control, fn ->
          State.current!()
          |> State.store!(%Decision{state: :protected, target_w: 85, trim: true}, @now)
        end)

      assert State.stored(state) == {%Decision{state: :protected, target_w: 85, trim: true}, @now}

      assert Tick.previous(state, DateTime.add(@now, 149)) == %Decision{
               state: :protected,
               target_w: 85,
               trim: true
             }

      assert Tick.previous(state, DateTime.add(@now, 150)) == nil
    end

    test "needs both the state and the time" do
      assert State.stored(%State{decision_state: nil, last_decision_at: @now}) == nil
      assert State.stored(%State{decision_state: "normal", last_decision_at: nil}) == nil
    end

    test "an unknown state is refused, not read as normal" do
      assert_raise ArgumentError, fn ->
        State.stored(%State{decision_state: "bogus", last_decision_at: @now})
      end
    end

    test "resume clears it, pause keeps it" do
      Ownership.override(%{solakon_monitor: :phoenix, solakon_control: :phoenix})

      Repo.write(:solakon_control, fn ->
        state =
          State.current!()
          |> State.store!(%Decision{state: :surplus, target_w: 500, trim: false}, @now)
          |> State.pause!()

        assert State.stored(state)
        state = State.resume!(state)
        assert State.active?(state)
        assert State.stored(state) == nil
        assert {state.trim, state.last_target_w} == {false, nil}
      end)
    end
  end

  describe "the guaranteed floor" do
    test "is memoized for an hour, the live sum read fresh" do
      ts = DateTime.to_unix(@now)
      insert_sample!("fridge", ts - 100, 120, 1)

      assert %Load{current_w: 120.0, floor_w: 120.0} = LoadReader.load_estimate(roster(), @now)

      insert_sample!("fridge", ts + 10, 60, 1)
      later = DateTime.add(@now, 15)
      assert %Load{current_w: 60.0, floor_w: 120.0} = LoadReader.load_estimate(roster(), later)

      much_later = DateTime.add(@now, 3600)
      assert %Load{floor_w: 60.0} = LoadReader.load_estimate(roster(), much_later)
    end

    test "is zero without consumers, and the live sum unknown" do
      assert LoadReader.load_estimate(Roster.new([]), @now) == %Load{current_w: nil, floor_w: 0.0}
    end
  end

  describe "the outcome's log line" do
    test "reports every control input of an applied tick" do
      outcome = %Outcome{
        status: :applied,
        decision: %Decision{state: :surplus, target_w: 485, trim: false},
        load: Load.new(123.6, 84.6),
        reading:
          reading(battery_soc_pct: 100, battery_temperature_c: 30.5, battery_power_w: -15.5)
      }

      assert Outcome.log_level(outcome) == :info

      assert Outcome.log_line(outcome) ==
               "state=surplus target=485W load=124W floor=85W soc=100% temp=30.5C pv=0.0W battery=-15.5W"
    end

    test "names failures and the release" do
      assert Outcome.log_line(%Outcome{status: :paused}) == "runtime paused"
      failed = %Outcome{status: :failed, failures: 2, error: "down"}
      assert Outcome.log_line(failed) == "Modbus failure 2/3: down"
      assert Outcome.log_level(failed) == :warning

      assert Outcome.log_line(%{failed | status: :released, failures: 3}) ==
               "Modbus failure 3/3: down — relinquished remote control"
    end
  end
end
