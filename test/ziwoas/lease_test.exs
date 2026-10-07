defmodule Ziwoas.LeaseTest do
  # Leases are VM-wide (a named table, `config :ziwoas, leases:`).
  use Ziwoas.DataCase, async: false

  import ExUnit.CaptureLog

  alias Ziwoas.{Clock, Lease, Ownership, Repo}
  alias Ziwoas.Ownership.NotOwnerError

  @now ~U[2026-10-05 10:00:00.000000Z]

  setup %{repo: repo} do
    Application.put_env(:ziwoas, :leases, true)
    Repo.put_writer(:main, repo)
    {:ok, clock} = Agent.start_link(fn -> @now end)
    Process.put(:lease_clock, clock)
    Clock.freeze(@now)
    Ownership.override(%{lights: :phoenix, switching: :phoenix, weather: :phoenix})

    on_exit(fn ->
      Application.put_env(:ziwoas, :leases, false)
      Ownership.clear_override()
    end)
  end

  defp rails_holds(task, at) do
    Repo.query!(
      "INSERT INTO migration_leases (task, holder, heartbeat_at) VALUES (?1, 'rails', ?2)",
      [Atom.to_string(task), at]
    )
  end

  defp rows,
    do: Repo.query!("SELECT task, holder, heartbeat_at FROM migration_leases ORDER BY task").rows

  # The heartbeat's clock and this process's (held?/1) stand at the same instant.
  defp start_lease!(tasks) do
    clock = Process.get(:lease_clock)
    start_supervised!({Lease, tasks: tasks, clock: fn -> Agent.get(clock, & &1) end})
  end

  defp set_now(instant) do
    Agent.update(Process.get(:lease_clock), fn _ -> instant end)
    Clock.freeze(instant)
  end

  test "the owned ingest and effect tasks have leases, route tasks none" do
    owners = %{Ownership.all_rails() | weather: :phoenix, economics: :phoenix, lights: :dry_run}

    assert Lease.tasks(owners) == [:weather]
    refute Lease.leased?(:economics)
    assert Lease.leased?(:solakon_control)
  end

  test "free leases are taken before start returns, the heartbeat in Rails' format" do
    start_lease!([:lights, :weather])

    assert rows() == [
             ["lights", "phoenix", "2026-10-05 10:00:00"],
             ["weather", "phoenix", "2026-10-05 10:00:00"]
           ]

    assert Lease.held?(:lights)
    assert Ownership.ensure_owner!(:lights) == :ok
    assert Ownership.acting?(:weather)
  end

  test "a fresh Rails heartbeat is refused loudly: Phoenix neither sends nor writes" do
    rails_holds(:lights, "2026-10-05 09:59:00")

    log = capture_log(fn -> start_lease!([:lights]) end)

    assert log =~
             "lease: rails holds lights (heartbeat 2026-10-05 09:59:00): Phoenix does not act for it"

    assert rows() == [["lights", "rails", "2026-10-05 09:59:00"]]
    refute Lease.held?(:lights)
    refute Ownership.acting?(:lights)

    error = assert_raise NotOwnerError, fn -> Ownership.ensure_owner!(:lights) end
    assert error.lease == "rails"

    assert Exception.message(error) ==
             "lights: rails holds its lease, so Phoenix does not act for it"

    assert_raise NotOwnerError, fn -> Repo.write(:lights, fn -> :written end) end
  end

  test "a fresh foreign lease blocks a device send" do
    rails_holds(:lights, "2026-10-05 09:59:30")
    capture_log(fn -> start_lease!([:lights]) end)
    test = self()
    Ziwoas.Mqtt.record(fn _client, topic, _payload -> send(test, {:sent, topic}) end)

    assert_raise NotOwnerError, fn ->
      Ziwoas.Mqtt.publish(:lights, "ziwoas-phoenix-command", "govees/L1/set", "{}")
    end

    refute_received {:sent, _}
  end

  test "a fresh foreign lease blocks a job run" do
    rails_holds(:weather, "2026-10-05 09:59:30")
    capture_log(fn -> start_lease!([:weather]) end)
    test = self()
    clock_agent = Process.get(:lease_clock)

    runner =
      start_supervised!(
        {Ziwoas.Scheduler.Runner,
         id: :fetch_current_weather,
         task: :weather,
         schedule: "every 15 minutes",
         job: Ziwoas.Scheduler.TestJob,
         zone: "Europe/Berlin",
         clock: fn -> Agent.get(clock_agent, & &1) end,
         timer: fn pid, message, _delay -> send(test, {:armed, pid, message}) end}
      )

    assert_receive {:armed, ^runner, {:due, due}}
    set_now(due)

    log =
      capture_log(fn ->
        send(runner, {:due, due})
        assert_receive {:armed, ^runner, _next}
      end)

    refute_received {:performed, _}
    assert log =~ "scheduler: fetch_current_weather skipped: rails holds the lease of weather"
  end

  test "a stale Rails heartbeat (two intervals) is taken over" do
    rails_holds(:lights, "2026-10-05 09:58:59.999999")
    start_lease!([:lights])

    assert rows() == [["lights", "phoenix", "2026-10-05 10:00:00"]]
    assert Lease.held?(:lights)
  end

  test "the heartbeat renews; without one the hold lapses after two intervals" do
    lease = start_lease!([:lights])

    set_now(~U[2026-10-05 10:00:59.999999Z])
    assert Lease.held?(:lights)
    set_now(~U[2026-10-05 10:01:00.000000Z])
    refute Lease.held?(:lights)

    send(lease, :beat)
    :sys.get_state(lease)

    assert Lease.held?(:lights)
    assert rows() == [["lights", "phoenix", "2026-10-05 10:01:00"]]
  end

  test "Rails taking a stale lease is seen at the next heartbeat" do
    lease = start_lease!([:lights])
    set_now(~U[2026-10-05 10:01:30.000000Z])

    Repo.query!(
      "UPDATE migration_leases SET holder = 'rails', heartbeat_at = '2026-10-05 10:01:20'"
    )

    capture_log(fn ->
      send(lease, :beat)
      :sys.get_state(lease)
    end)

    refute Lease.held?(:lights)
    assert Lease.holder(:lights) == "rails"
  end

  test "a clean stop hands the leases back" do
    rails_holds(:weather, "2026-10-05 09:59:30")
    capture_log(fn -> start_lease!([:lights, :weather]) end)

    stop_supervised!(Lease)

    assert rows() == [["weather", "rails", "2026-10-05 09:59:30"]]
    refute Lease.held?(:lights)
  end

  test "an owned route answers 503 while Rails holds the lease, 421 when not owned" do
    rails_holds(:switching, "2026-10-05 09:59:30")
    capture_log(fn -> start_lease!([:lights, :switching]) end)
    call = fn task -> ZiwoasWeb.Owned.call(Phoenix.ConnTest.build_conn(), task).status end

    assert call.(:lights) == nil
    assert call.(:switching) == 503
    assert call.(:solakon_control) == 421
  end

  test "with leases off (tests) and for tasks without one, Phoenix always holds" do
    Application.put_env(:ziwoas, :leases, false)
    assert Lease.held?(:lights)

    Application.put_env(:ziwoas, :leases, true)
    assert Lease.held?(:economics)
    refute Lease.held?(:lights), "no heartbeat yet: no lease"
  end
end
