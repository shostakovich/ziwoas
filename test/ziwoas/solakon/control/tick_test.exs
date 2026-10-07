defmodule Ziwoas.Solakon.Control.TickTest do
  use Ziwoas.DataCase

  alias Ziwoas.{FakeModbusServer, Repo, TestClock}
  alias Ziwoas.Plugs.{Plug, Roster}
  alias Ziwoas.Solakon.Control.{Decision, Load, LoadReader, Outcome, State, Tick}
  alias Ziwoas.Solakon.{Monitor, Reading}

  @moduletag :capture_log
  @now ~U[2026-10-05 10:00:00.000000Z]

  setup do
    TestClock.freeze(@now)
    :ok
  end

  defp roster, do: Roster.new([%Plug{id: "fridge", name: "Kühlschrank", role: :consumer}])

  defp reading(attrs),
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

  describe "the stored decision" do
    test "round-trips and expires with the inverter's watchdog" do
      state =
        State.current!()
        |> State.store!(%Decision{state: :protected, target_w: 85, trim: true}, @now)

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
      state =
        State.current!()
        |> State.store!(%Decision{state: :surplus, target_w: 500, trim: false}, @now)
        |> State.pause!()

      assert State.stored(state)
      state = State.resume!(state)
      assert State.active?(state)
      assert State.stored(state) == nil
      assert {state.trim, state.last_target_w} == {false, nil}
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

  describe "a tick" do
    setup do
      insert_sample!("fridge", DateTime.to_unix(@now) - 10, 300, 1)
      :ok
    end

    # The inverter holds the minimum SoC already, so a tick writes 46001, 46002 and 46003.
    defp inverter!(opts \\ []) do
      server = start_supervised!({FakeModbusServer, {%{"46609:1" => [10]}, opts}})

      monitor =
        start_supervised!(
          {Monitor,
           name: nil, host: "127.0.0.1", port: FakeModbusServer.port(server), io_timeout_ms: 500}
        )

      {server, monitor}
    end

    defp frames(server), do: server |> FakeModbusServer.frames() |> List.flatten()
    defp tick(monitor), do: Tick.run(reading([]), roster(), @now, monitor: monitor)

    test "writes the target, then stores the decision that reached the inverter" do
      {server, monitor} = inverter!()

      assert %Outcome{status: :applied, decision: decision} = tick(monitor)
      assert decision == %Decision{state: :normal, target_w: 300, trim: false}

      assert frames(server) == [
               "0001000000060103b6110001",
               "0002000000060106b3b10001",
               "0003000000060106b3b20096",
               "00040000000b0110b3b30002040000012c"
             ]

      state = State.current()
      assert State.stored(state) == {decision, @now}
      assert state.consecutive_failures == 0
    end

    test "a refused write counts as a failure and stores no decision" do
      {_server, monitor} = inverter!(fail: ["16:46003"])

      assert tick(monitor) == %Outcome{
               status: :failed,
               failures: 1,
               error: "{:modbus_exception, 4}"
             }

      state = State.current()
      assert state.consecutive_failures == 1
      assert State.stored(state) == nil
    end

    test "the third failure in a row hands control back and forgets the decision" do
      {server, monitor} = inverter!(fail: ["16:46003"])
      State.store!(State.current!(), %Decision{state: :normal, target_w: 250, trim: false}, @now)

      assert [%{status: :failed, failures: 1}, %{status: :failed, failures: 2}] =
               [tick(monitor), tick(monitor)]

      assert State.stored(State.current())

      assert %Outcome{status: :released, failures: 3, error: "{:modbus_exception, 4}"} =
               tick(monitor)

      assert List.last(frames(server)) == "0001000000060106b3b10000"

      state = State.current()
      assert state.consecutive_failures == 0
      assert State.stored(state) == nil
    end

    test "a release the inverter refuses keeps counting and says so" do
      {_server, monitor} = inverter!(fail: ["6:46001"])
      Repo.insert!(%State{consecutive_failures: 2})

      assert %Outcome{status: :failed, failures: 3, error: error} = tick(monitor)
      assert error =~ "could not relinquish remote control: {:modbus_exception, 4}"

      assert %Outcome{status: :failed, failures: 4} = tick(monitor)
      assert State.current().consecutive_failures == 4
    end

    test "a monitor that is down counts as a failed write" do
      monitor = spawn(fn -> :ok end)
      ref = Process.monitor(monitor)
      assert_receive {:DOWN, ^ref, :process, _, _}
      Repo.insert!(%State{consecutive_failures: 2})

      assert %Outcome{status: :failed, failures: 3, error: error} = tick(monitor)
      assert error =~ "monitor_down"
      assert error =~ "could not relinquish remote control"
    end

    test "a successful write clears earlier failures" do
      {_server, monitor} = inverter!()
      Repo.insert!(%State{consecutive_failures: 2})

      assert %Outcome{status: :applied} = tick(monitor)
      assert State.current().consecutive_failures == 0
    end

    test "a paused loop decides nothing and writes nothing" do
      {server, monitor} = inverter!()
      Repo.insert!(%State{paused: true})

      assert tick(monitor) == %Outcome{status: :paused}
      assert FakeModbusServer.frames(server) == []
      assert State.stored(State.current()) == nil
    end

    test "continues the stored decision while the watchdog holds it" do
      {_server, monitor} = inverter!()
      stored_at = DateTime.add(@now, -30)

      State.store!(
        State.current!(),
        %Decision{state: :normal, target_w: 50, trim: false},
        stored_at
      )

      assert %Outcome{decision: %Decision{target_w: 250}} = tick(monitor)
    end
  end
end
