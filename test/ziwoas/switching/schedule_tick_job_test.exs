defmodule Ziwoas.Switching.ScheduleTickJobTest do
  # Mirrors test/jobs/schedule_tick_job_test.rb where the decision vectors
  # (test/vectors/schedule_tick_test.exs) do not reach: the job's entry point, its
  # log, and the dry run's two worlds.
  use Ziwoas.DataCase, async: true

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Ziwoas.{Clock, Mqtt, Ownership, Repo}
  alias Ziwoas.Switching.{Command, Rules, ScheduleTickJob, SchedulerState}

  @moduletag :tmp_dir
  # Monday 2026-06-15 18:05 in Berlin.
  @now "2026-06-15T18:05:00+02:00"

  setup %{repo: repo} do
    Clock.freeze(@now)
    Repo.put_writer(:main, repo)
    on_exit(&Ownership.clear_override/0)
    test = self()

    Mqtt.record(fn _client, topic, payload ->
      send(test, {:published, topic, payload})

      if String.contains?(topic, "/fridge/") and Process.get(:broker_down),
        do: {:error, :econnrefused},
        else: :ok
    end)

    # test/fixtures/ziwoas.test.yml: fridge switches.
    %{config: Ziwoas.Config.app_config()}
  end

  defp window!(on, off) do
    Ownership.override(%{switch_schedule: :phoenix})
    Rules.save_window("fridge", %{on_at_time: on, off_at_time: off, days: [1]})
  end

  defp watermark!(time),
    do: Repo.insert!(%SchedulerState{plug_id: "fridge", last_tick_at: Clock.parse!(time)})

  defp in_repo(repo, fun) do
    previous = Repo.get_dynamic_repo()
    Repo.put_dynamic_repo(repo)

    try do
      fun.()
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  test "perform switches the edge between watermark and now and moves the watermark", ctx do
    window!("18:00", "23:00")
    Ownership.override(%{switching: :phoenix})
    watermark!("2026-06-15T17:55:00+02:00")

    ScheduleTickJob.perform(%{
      task: :switching,
      mode: :phoenix,
      at: Clock.now(),
      config: ctx.config
    })

    assert_received {:published, "shellies/fridge/command/switch:0", "on"}
    assert [%Command{action: "on", source: "schedule"}] = Repo.all(Command)
    assert SchedulerState.last_tick_at("fridge") == Clock.now()
  end

  test "the warning names the plug, the rule and the reason; the watermark stays", ctx do
    window!("18:00", "23:00")
    Ownership.override(%{switching: :phoenix})
    watermark!("2026-06-15T17:55:00+02:00")
    Process.put(:broker_down, true)
    [on | _] = Repo.all(from r in Ziwoas.Switching.Rule, order_by: [desc: r.action])

    log = capture_log(fn -> ScheduleTickJob.tick(ctx.config, Clock.now()) end)

    assert log =~ "fridge"
    assert log =~ "rule #{on.id}"
    assert log =~ "econnrefused"
    assert Repo.all(Command) == []

    assert DateTime.compare(
             SchedulerState.last_tick_at("fridge"),
             Clock.parse!("2026-06-15T17:55:00+02:00")
           ) == :eq
  end

  test "a dry run decides from Rails' rules and manual commands, keeps its own watermark and sends nothing",
       %{config: config, repo: main, tmp_dir: dir} do
    window!("18:00", "23:00")
    # Rails' watermark already passed the edge: the dry run must not follow it.
    watermark!("2026-06-15T18:04:00+02:00")

    shadow =
      start_supervised!(
        {Repo,
         name: nil,
         database: Ziwoas.RailsFixture.build!(Path.join(dir, "shadow.sqlite3"), rows: false),
         writable: true,
         pool_size: 1}
      )

    Repo.put_writer(:shadow, shadow)
    Ownership.override(%{switching: :dry_run})

    ScheduleTickJob.tick(config, Clock.now())

    refute_received {:published, _, _}
    assert Repo.all(Command) == []

    in_repo(shadow, fn ->
      assert [%Command{plug_id: "fridge", action: "on", source: "schedule"}] = Repo.all(Command)
      assert SchedulerState.last_tick_at("fridge") == Clock.now()
    end)

    # A manual switch in Rails' world after the edge keeps the next dry tick quiet.
    in_repo(main, fn ->
      Repo.insert!(%Command{plug_id: "fridge", action: "off", source: "manual"})
    end)

    in_repo(shadow, fn -> Repo.delete_all(SchedulerState) end)
    ScheduleTickJob.tick(config, Clock.now())
    in_repo(shadow, fn -> assert length(Repo.all(Command)) == 1 end)
  end
end
