defmodule Ziwoas.Live.DashboardWatcherTest do
  # The bridge in place of test/dashboard_broadcaster_test.rb and the
  # broadcast half of test/shelly_status_handler_test.rb: what the collector
  # broadcasts after a Shelly report, the watcher broadcasts when a sample shows up.
  # The watcher queries from its own process, from its first moment on.
  use Ziwoas.DataCase

  import ExUnit.CaptureLog

  alias Ziwoas.{Config, Repo}
  alias Ziwoas.Live.DashboardWatcher
  alias Ziwoas.Plugs.State

  @moduletag :shared_sandbox

  defp start_watcher!(opts \\ []),
    do:
      start_supervised!(
        {DashboardWatcher, [name: nil, interval_ms: 10] ++ opts},
        id: make_ref()
      )

  setup do
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "dashboard")
    :ok
  end

  test "a new sample is a live beat carrying the reporting plug's delta" do
    insert_sample!("fridge", 1_000_025, 10.0, 1.0)
    start_watcher!()
    refute_receive {:dashboard_live, _}, 50

    insert_sample!("fridge", 1_000_045, 80.0, 2.0)

    assert_receive {:dashboard_live, [delta]}

    assert delta == [
             {"id", "fridge"},
             {"name", "Kühlschrank"},
             {"role", :consumer},
             {"apower_w", 80.0},
             {"last_seen_ts", 1_000_045},
             {"bucket_ts", 1_000_020},
             {"avg_power_w", 45.0},
             {"output", nil}
           ]

    refute_receive {:dashboard_live, _}, 50
  end

  test "standing down for plug_ingest it sends only the summary beat" do
    start_watcher!(live: false, summary_interval_ms: 20)
    insert_sample!("bkw", 1_000_020, -300.0, 1.0)

    assert_receive {:dashboard_summary}
    refute_received {:dashboard_live, _}
  end

  test "the first sample in an empty table counts as new" do
    start_watcher!()
    insert_sample!("bkw", 1_000_020, -300.0, 1.0)

    assert_receive {:dashboard_live, [delta]}
    assert {"avg_power_w", 300.0} in delta, "a producer's mean is positive, like the 24 h chart"
  end

  test "an unreadable table at start: the first rowid read later is the baseline" do
    insert_sample!("bkw", 1_000_020, -300.0, 1.0)
    Repo.query!("ALTER TABLE samples RENAME TO samples_away")

    capture_log(fn ->
      start_watcher!()
      Process.sleep(30)
    end)

    Repo.query!("ALTER TABLE samples_away RENAME TO samples")
    refute_receive {:dashboard_live, _}, 50

    insert_sample!("fridge", 1_000_045, 80.0, 2.0)
    assert_receive {:dashboard_live, [delta]}
    assert {"id", "fridge"} in delta
  end

  test "without a subscriber no deltas are read, but the baseline moves on" do
    test = self()

    :telemetry.attach(
      "dashboard-watcher-test",
      [:ziwoas, :repo, :query],
      fn _event, _measurements, %{query: query}, _ ->
        if query =~ "GROUP BY +plug_id", do: send(test, :deltas_read)
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach("dashboard-watcher-test") end)

    Phoenix.PubSub.unsubscribe(Ziwoas.PubSub, "dashboard")
    start_watcher!()
    insert_sample!("bkw", 1_000_020, -300.0, 1.0)
    refute_receive :deltas_read, 50

    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "dashboard")
    insert_sample!("fridge", 1_000_045, 80.0, 2.0)

    assert_receive {:dashboard_live, [delta]}
    assert {"id", "fridge"} in delta
    assert_received :deltas_read
  end

  test "the delta query seeks the rowid range instead of scanning an index" do
    %{rows: plan} =
      Repo.query!(
        "EXPLAIN QUERY PLAN SELECT plug_id, MAX(ts) FROM samples WHERE rowid > 1 GROUP BY +plug_id"
      )

    assert Enum.any?(plan, fn row -> List.last(row) =~ "USING INTEGER PRIMARY KEY (rowid>?)" end)
  end

  test "the summary beat fires on its own clock" do
    start_watcher!(summary_interval_ms: 20)

    assert_receive {:dashboard_summary}
    assert_receive {:dashboard_summary}
  end

  test "deltas: one per configured plug that reported, in roster order, with its output" do
    roster = Config.plug_roster(Config.app_config())
    insert_sample!("fridge", 1_000_000, 10.0, 1.0)
    insert_sample!("fridge", 1_000_030, 20.0, 1.0)
    insert_sample!("fridge", 1_000_070, 30.0, 1.0)
    insert_sample!("bkw", 1_000_010, -100.0, 1.0)
    insert_sample!("old_heater", 1_000_010, 900.0, 1.0)
    Repo.insert!(%State{plug_id: "fridge", output: true})

    assert [bkw, fridge] = DashboardWatcher.deltas(roster, nil)
    assert {"id", "bkw"} in bkw

    assert {"avg_power_w", 25.0} in fridge,
           "only the newest sample's minute: 1_000_020 – 1_000_079"

    assert {"output", true} in fridge
    assert {"apower_w", 30.0} in fridge

    %{rows: [[rowid]]} = Repo.query!("SELECT MAX(rowid) FROM samples")
    assert DashboardWatcher.deltas(roster, rowid) == []
  end
end
