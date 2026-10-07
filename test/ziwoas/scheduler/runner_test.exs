defmodule Ziwoas.Scheduler.RunnerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ziwoas.Scheduler.{FailingTestJob, Runner, TestJob}

  setup do
    {:ok, clock} = Agent.start_link(fn -> ~U[2026-10-05 10:00:00.000000Z] end)
    test = self()

    opts = [
      id: :poll_sensors,
      task: :sensor_poll,
      schedule: "every 15 minutes",
      job: TestJob,
      zone: "Europe/Berlin",
      clock: fn -> Agent.get(clock, & &1) end,
      timer: fn pid, message, delay ->
        send(test, {:armed, pid, message, delay})
        make_ref()
      end
    ]

    %{clock: clock, opts: opts}
  end

  defp set_clock(clock, instant), do: Agent.update(clock, fn _ -> instant end)

  defp start!(opts), do: start_supervised!({Runner, opts})

  test "arms for the next due instant", %{opts: opts} do
    pid = start!(opts)

    assert_receive {:armed, ^pid, {:due, ~U[2026-10-05 10:15:00Z]}, 900_000}
  end

  test "runs with the mode in effect, then re-arms", %{clock: clock, opts: opts} do
    pid = start!(opts)
    assert_receive {:armed, ^pid, {:due, due}, _}

    set_clock(clock, ~U[2026-10-05 10:15:02.000000Z])
    send(pid, {:due, due})

    assert_receive {:performed, %{task: :sensor_poll, mode: :phoenix, at: ^due}}
    assert_receive {:armed, ^pid, {:due, ~U[2026-10-05 10:30:00Z]}, 898_000}
  end

  test "the owner keeps the schedule's instants despite a shadow offset", %{opts: opts} do
    pid = start!(Keyword.put(opts, :shadow_offset, 40))

    assert_receive {:armed, ^pid, {:due, ~U[2026-10-05 10:15:00Z]}, 900_000}
  end

  test "a timer ahead of the clock waits out the rest without running", %{
    clock: clock,
    opts: opts
  } do
    pid = start!(opts)
    assert_receive {:armed, ^pid, {:due, due}, _}

    set_clock(clock, ~U[2026-10-05 10:14:59.750000Z])
    send(pid, {:due, due})

    assert_receive {:armed, ^pid, {:due, ^due}, 250}
    refute_received {:performed, _}
  end

  test "a stale wake-up is ignored", %{opts: opts} do
    pid = start!(opts)
    assert_receive {:armed, ^pid, _, _}

    send(pid, {:due, ~U[2026-10-05 09:45:00Z]})

    refute_receive {:performed, _}, 50
    refute_received {:armed, _, _, _}
  end

  test "a run past the next due instant skips it", %{clock: clock, opts: opts} do
    pid = start!(opts)
    assert_receive {:armed, ^pid, {:due, due}, _}

    set_clock(clock, ~U[2026-10-05 10:47:00.000000Z])
    send(pid, {:due, due})

    assert_receive {:performed, %{at: ^due}}
    assert_receive {:armed, ^pid, {:due, ~U[2026-10-05 11:00:00Z]}, 780_000}
  end

  test "a failing job is logged and the schedule goes on", %{clock: clock, opts: opts} do
    pid = start!(Keyword.put(opts, :job, FailingTestJob))
    assert_receive {:armed, ^pid, {:due, due}, _}
    set_clock(clock, due)

    log =
      capture_log(fn ->
        send(pid, {:due, due})
        assert_receive {:performed, %{mode: :phoenix}}
        assert_receive {:armed, ^pid, {:due, ~U[2026-10-05 10:30:00Z]}, _}
      end)

    assert log =~ "scheduler: poll_sensors (phoenix) failed"
    assert log =~ "job failed"
    assert Process.alive?(pid)
  end

  test "an unknown task stops the runner from starting", %{opts: opts} do
    assert {:error, {{%ArgumentError{message: "unknown task :wether"}, _}, _}} =
             start_supervised({Runner, Keyword.put(opts, :task, :wether)})
  end

  test "the supervisor starts one runner per configured job", %{opts: opts} do
    jobs = [
      poll_sensors: [task: :sensor_poll, schedule: "every 15 minutes", job: TestJob],
      fetch_current_weather: [task: :weather, schedule: "every 15 minutes", job: TestJob]
    ]

    sup =
      start_supervised!(
        {Ziwoas.Scheduler, [name: nil, jobs: jobs] ++ Keyword.take(opts, [:zone, :clock, :timer])}
      )

    assert sup |> Supervisor.which_children() |> Enum.map(&elem(&1, 0)) |> Enum.sort() ==
             [:fetch_current_weather, :poll_sensors]
  end
end
