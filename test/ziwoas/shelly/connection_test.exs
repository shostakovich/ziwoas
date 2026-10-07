defmodule Ziwoas.Shelly.ConnectionTest do
  # The WebSock callbacks run in the test process, which stands in for the connection.
  use Ziwoas.DataCase

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Ziwoas.{Config, Repo, Shelly, TestConfigs}
  alias Ziwoas.Plugs.{Roster, Sample, State}
  alias Ziwoas.Shelly.Connection

  @moduletag :capture_log
  @now 1_700_000_000

  setup do
    clock = :counters.new(1, [])
    :counters.put(clock, 1, @now)
    %{clock: clock}
  end

  defp plug(id), do: TestConfigs.plugs() |> Config.plug_roster() |> Roster.find(id)

  defp connect(ctx, id \\ "fridge", ingest \\ []) do
    test = self()

    ingest =
      Keyword.merge(
        [
          clock: fn -> :counters.get(ctx.clock, 1) * 1.0 end,
          broadcast: &send(test, {:broadcast, &1})
        ],
        ingest
      )

    {:push, {:text, request}, state} =
      Connection.init(%{plug: plug(id), peer: "10.0.0.5", ingest: ingest})

    {JSON.decode!(request), state}
  end

  defp tick(ctx, seconds), do: :counters.add(ctx.clock, 1, seconds)

  defp in_5s, do: System.monotonic_time(:millisecond) + 5_000

  defp frame(state, frame) do
    {:ok, state} = Connection.handle_in({JSON.encode!(frame), opcode: :text}, state)
    state
  end

  defp notify(state, method, switch, extra \\ %{}),
    do: frame(state, %{"method" => method, "params" => Map.put(extra, "switch:0", switch)})

  defp switch(apower, total, output \\ true),
    do: %{"id" => 0, "output" => output, "apower" => apower, "aenergy" => %{"total" => total}}

  test "on connect it registers for the plug and asks for the full status", ctx do
    {request, _state} = connect(ctx)

    assert %{"id" => 1, "src" => "ziwoas", "method" => "Shelly.GetStatus"} = request
    assert Shelly.connection("fridge") == self()
  end

  test "a full status becomes a sample, the relay output and a live delta", ctx do
    {_request, state} = connect(ctx)

    notify(state, "NotifyFullStatus", switch(50, 1.5))

    assert [%Sample{plug_id: "fridge", ts: @now, apower_w: 50.0, aenergy_wh: 1.5}] =
             Repo.all(Sample)

    assert [%State{plug_id: "fridge", output: true}] = Repo.all(State)
    assert_received {:broadcast, [%{id: "fridge", apower_w: 50.0, output: true}]}
  end

  test "the answer to Shelly.GetStatus is a full status", ctx do
    {%{"id" => id}, state} = connect(ctx)

    frame(state, %{"id" => id, "src" => "shelly", "result" => %{"switch:0" => switch(20, 3.0)}})

    assert [%Sample{apower_w: 20.0, aenergy_wh: 3.0}] = Repo.all(Sample)
  end

  test "a delta is merged into the status it keeps", ctx do
    {_request, state} = connect(ctx)
    state = notify(state, "NotifyFullStatus", switch(50, 1.5))

    tick(ctx, 10)
    state = notify(state, "NotifyStatus", %{"apower" => 80})
    tick(ctx, 50)
    notify(state, "NotifyStatus", %{"aenergy" => %{"total" => 2.0}})

    assert [{50.0, 1.5}, {80.0, 1.5}, {80.0, 2.0}] =
             Repo.all(from s in Sample, order_by: s.ts, select: {s.apower_w, s.aenergy_wh})
  end

  test "a relay change in the same second as a sample still reaches the relay state", ctx do
    {_request, state} = connect(ctx)
    state = notify(state, "NotifyFullStatus", switch(50, 1.5, true))

    notify(state, "NotifyStatus", %{"output" => false, "source" => "button"})

    assert [%Sample{}] = Repo.all(Sample)
    assert [%State{output: false}] = Repo.all(State)
  end

  test "a relay change alone records no sample, so new watts in that second still count", ctx do
    {_request, state} = connect(ctx)
    state = notify(state, "NotifyFullStatus", switch(50, 1.5, true))
    assert_received {:broadcast, [%{apower_w: 50.0}]}

    tick(ctx, 10)
    state = notify(state, "NotifyStatus", %{"output" => false, "source" => "button"})
    state = notify(state, "NotifyStatus", %{"apower" => 0})
    {:ok, _state} = Connection.handle_info(:flush, state)

    assert [{@now, 50.0}, {1_700_000_010, +0.0}] =
             Repo.all(from s in Sample, order_by: s.ts, select: {s.ts, s.apower_w})

    assert_received {:broadcast, [%{apower_w: 50.0, output: false}]}
    assert_received {:broadcast, [%{apower_w: +0.0, output: false}]}
  end

  test "a relay change in the same second as a sample goes out as a live delta", ctx do
    {_request, state} = connect(ctx)
    state = notify(state, "NotifyFullStatus", switch(50, 1.5, true))
    assert_received {:broadcast, [%{output: true}]}

    state = notify(state, "NotifyStatus", %{"output" => false, "source" => "button"})
    assert is_reference(state.flush_timer)
    {:ok, _state} = Connection.handle_info(:flush, state)

    assert_received {:broadcast, [%{id: "fridge", apower_w: 50.0, output: false}]}
  end

  test "frames without switch:0 and events change nothing", ctx do
    {_request, state} = connect(ctx)

    assert frame(state, %{"method" => "NotifyStatus", "params" => %{"wifi" => %{"rssi" => -60}}}) ==
             state

    events = %{"events" => [%{"component" => "input:0", "event" => "single_push"}]}
    assert frame(state, %{"method" => "NotifyEvent", "params" => events}) == state
    assert frame(state, %{"id" => 99, "result" => %{}}) == state
    assert Repo.all(Sample) == []
  end

  test "a delta before any full status records nothing", ctx do
    {_request, state} = connect(ctx)

    notify(state, "NotifyStatus", %{"apower" => 80})
    assert Repo.all(Sample) == []
  end

  test "a full status without metering is logged and records nothing", ctx do
    {_request, state} = connect(ctx)

    log = capture_log(fn -> notify(state, "NotifyFullStatus", %{"id" => 0, "output" => true}) end)

    assert log =~ "Shelly fridge: status without apower or aenergy.total"
    assert Repo.all(Sample) == []
  end

  test "broken JSON is logged and dropped", ctx do
    {_request, state} = connect(ctx)

    log =
      capture_log(fn ->
        assert Connection.handle_in({~s({"method": ), opcode: :text}, state) == {:ok, state}
        assert Connection.handle_in({"[1, 2]", opcode: :text}, state) == {:ok, state}
      end)

    assert log =~ "Shelly fridge: invalid JSON frame"
  end

  test "a failing write is logged and keeps the connection", ctx do
    {_request, state} = connect(ctx, "fridge", broadcast: fn _deltas -> raise "boom" end)

    log =
      capture_log(fn ->
        assert %{switch: %{"apower" => 50}} = notify(state, "NotifyFullStatus", switch(50, 1.5))
      end)

    assert log =~ "Shelly fridge: recording failed: boom"
  end

  describe "the live deltas" do
    test "a plug that pauses gets its waiting delta out on the flush", ctx do
      {_request, state} = connect(ctx)
      state = notify(state, "NotifyFullStatus", switch(50, 1.5))
      assert_received {:broadcast, [%{apower_w: 50.0}]}

      tick(ctx, 1)
      state = notify(state, "NotifyStatus", %{"output" => false, "apower" => 0})
      refute_received {:broadcast, _}
      assert is_reference(state.flush_timer)

      {:ok, state} = Connection.handle_info(:flush, state)
      assert_received {:broadcast, [%{apower_w: +0.0, output: false}]}
      assert state.flush_timer == nil
    end

    test "a new minute starts a new mean", ctx do
      :counters.put(ctx.clock, 1, 1_700_000_039)
      {_request, state} = connect(ctx)

      state = notify(state, "NotifyFullStatus", switch(100, 1.0))
      assert_received {:broadcast, [%{bucket_ts: 1_699_999_980}]}

      tick(ctx, 10)
      notify(state, "NotifyStatus", %{"apower" => 300})
      assert_received {:broadcast, [%{bucket_ts: 1_700_000_040, avg_power_w: 300.0}]}
    end

    test "a producer's mean is a positive magnitude", ctx do
      {_request, state} = connect(ctx, "bkw")

      notify(state, "NotifyFullStatus", switch(-300, 1234.5))

      assert_received {:broadcast, [delta]}
      assert %{id: "bkw", role: :producer, apower_w: -300.0, avg_power_w: 300.0} = delta
    end
  end

  describe "RPC calls" do
    test "go out as requests; the answer goes back to the caller", ctx do
      {_request, state} = connect(ctx)
      reply_to = Process.alias()

      {:push, {:text, request}, state} =
        Connection.handle_info({:rpc, reply_to, "Switch.Set", %{id: 0, on: true}, in_5s()}, state)

      assert %{"id" => 2, "src" => "ziwoas", "method" => "Switch.Set"} = JSON.decode!(request)

      state = frame(state, %{"id" => 2, "src" => "shelly", "result" => %{"was_on" => false}})
      assert_received {^reply_to, {:ok, %{"was_on" => false}}}
      assert state.requests == %{1 => state.requests[1]}
    end

    test "a confirmed Switch.Set stores the relay output before the caller hears of it", ctx do
      {_request, state} = connect(ctx)
      state = notify(state, "NotifyFullStatus", switch(50, 1.5, true))
      reply_to = Process.alias()

      {:push, _request, state} =
        Connection.handle_info(
          {:rpc, reply_to, "Switch.Set", %{id: 0, on: false}, in_5s()},
          state
        )

      assert [%State{output: true}] = Repo.all(State)

      state = frame(state, %{"id" => 2, "result" => %{"was_on" => true}})
      assert [%State{output: false}] = Repo.all(State)
      assert_received {^reply_to, {:ok, %{"was_on" => true}}}

      {:ok, _state} = Connection.handle_info(:flush, state)
      assert_received {:broadcast, [%{id: "fridge", output: false}]}
    end

    test "a rejected Switch.Set leaves the relay output alone", ctx do
      {_request, state} = connect(ctx)
      reply_to = Process.alias()

      {:push, _request, state} =
        Connection.handle_info({:rpc, reply_to, "Switch.Set", %{id: 0, on: true}, in_5s()}, state)

      frame(state, %{"id" => 2, "error" => %{"code" => -103, "message" => "busy"}})
      assert Repo.all(State) == []
    end

    test "a call whose caller stopped waiting is not sent", ctx do
      {_request, state} = connect(ctx)
      expired = System.monotonic_time(:millisecond) - 1

      log =
        capture_log(fn ->
          assert Connection.handle_info(
                   {:rpc, Process.alias(), "Switch.Set", %{}, expired},
                   state
                 ) ==
                   {:ok, state}
        end)

      assert log =~ "Shelly fridge: Switch.Set dropped, its caller stopped waiting"
    end

    test "an error answer is the device's code and message", ctx do
      {_request, state} = connect(ctx)
      reply_to = Process.alias()

      {:push, _request, state} =
        Connection.handle_info({:rpc, reply_to, "Nope", %{}, in_5s()}, state)

      frame(state, %{"id" => 2, "error" => %{"code" => -114, "message" => "Method Nope failed"}})
      assert_received {^reply_to, {:error, {:rpc, -114, "Method Nope failed"}}}
    end

    test "the ping keeps the socket alive", ctx do
      {_request, state} = connect(ctx)
      assert {:push, {:ping, ""}, _state} = Connection.handle_info(:ping, state)
    end

    test "the ping drops requests nobody waits for any more", ctx do
      {_request, state} = connect(ctx)
      reply_to = Process.alias()

      {:push, _request, state} =
        Connection.handle_info({:rpc, reply_to, "Switch.Set", %{}, in_5s()}, state)

      long_ago = System.monotonic_time(:millisecond) - 31_000
      state = put_in(state.requests[2], {{:caller, reply_to}, long_ago})

      {:push, {:ping, ""}, state} = Connection.handle_info(:ping, state)
      assert Map.keys(state.requests) == [1]

      frame(state, %{"id" => 2, "result" => %{"was_on" => false}})
      refute_received {^reply_to, _reply}
    end
  end

  test "a newer connection for the plug replaces this one", ctx do
    {_request, state} = connect(ctx)
    test = self()

    newer =
      spawn_link(fn ->
        Connection.init(%{plug: plug("fridge"), peer: "10.0.0.6"})
        send(test, :connected)
        Process.sleep(:infinity)
      end)

    assert_receive :connected
    assert_received :replaced
    assert Shelly.connection("fridge") == newer
    assert {:stop, :normal, _state} = Connection.handle_info(:replaced, state)
    assert Registry.keys(Shelly.registry(), self()) == []
  end

  test "a connection that registered later is not replaced; the earlier one goes", ctx do
    test = self()

    later =
      spawn_link(fn ->
        Registry.register(Shelly.registry(), "fridge", System.monotonic_time() + 1_000_000_000)
        send(test, :registered)

        receive do
          message -> send(test, {:later_got, message})
        end

        receive do
          :done ->
            Registry.unregister(Shelly.registry(), "fridge")
            send(test, :done)
        end
      end)

    assert_receive :registered
    {_request, state} = connect(ctx)
    send(later, :probe)

    assert_receive {:later_got, :probe}
    assert Shelly.connection("fridge") == later
    assert_received :replaced
    assert {:stop, :normal, _state} = Connection.handle_info(:replaced, state)

    send(later, :done)
    assert_receive :done
  end

  test "a replaced connection keeps running once it is the newest again", ctx do
    {_request, state} = connect(ctx)
    test = self()

    spawn_link(fn ->
      Connection.init(%{plug: plug("fridge"), peer: "10.0.0.6"})
      Registry.unregister(Shelly.registry(), "fridge")
      send(test, :gone)
    end)

    assert_receive :gone
    assert_received :replaced
    assert {:ok, _state} = Connection.handle_info(:replaced, state)
    assert Shelly.connection("fridge") == self()
  end
end
