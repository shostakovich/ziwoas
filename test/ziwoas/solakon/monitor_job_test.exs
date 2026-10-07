defmodule Ziwoas.Solakon.MonitorJobTest do
  # test/jobs/solakon/monitor_job_test.rb and snapshot_job_test.rb: reading and storing,
  # where the rows go by mode. The control tick behind it: test/vectors/solakon_control_test.exs.
  # Subscribes to a global PubSub topic another test broadcasts on.
  use Ziwoas.DataCase, async: false

  alias Ziwoas.{Clock, Config, FakeModbusServer, Ownership, Repo}
  alias Ziwoas.Solakon.{Monitor, MonitorJob, Reading, Snapshot, SnapshotJob}

  @moduletag :capture_log

  @registers %{
    "39424:1" => [55],
    "39248:2" => [0, 123],
    "39279:8" => [0, 400, 0, 56, 0, 0, 0, 0],
    "39230:2" => [0xFFFF, 0xFFB2],
    "37617:1" => [423],
    "39227:1" => [512],
    "39228:2" => [0xFFFF, 0xFA24],
    "39141:1" => [341],
    "39063:1" => [4],
    "39065:2" => [0, 0],
    "39067:1" => [0],
    "39068:1" => [8],
    "39069:1" => [0],
    "46613:1" => [2],
    "39201:1" => [2301],
    "39216:2" => [0, 125],
    "39070:8" => [410, 512, 405, 488, 0, 0, 0, 0],
    "37609:1" => [513],
    "37610:1" => [42],
    "37611:1" => [248],
    "37618:1" => [211],
    "37624:1" => [97],
    "37626:6" => [0, 0, 0, 0, 0, 0],
    "37632:1" => [1234],
    "37633:1" => [512],
    "37635:1" => [19_200],
    "39168:2" => [0xFFFF, 0xFF9C],
    "39601:20" => [
      0,
      12_345,
      0,
      345,
      0,
      6789,
      0,
      120,
      0,
      4567,
      0,
      98,
      0,
      2222,
      0,
      55,
      0,
      3333,
      0,
      77
    ]
  }

  @now "2026-06-18T10:00:00Z"

  setup %{repo: repo} do
    Repo.put_writer(:main, repo)
    Clock.freeze(@now)
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "solakon")
    on_exit(&Ownership.clear_override/0)
    :ok
  end

  defp config(yaml \\ "") do
    Config.from_yaml!("""
    location:
      timezone: Europe/Berlin
    mqtt:
      host: localhost
      port: 1883
      topic_prefix: shellies
    plugs: []
    solakon:
      host: 127.0.0.1
    #{yaml}
    """)
  end

  defp monitor!(registers \\ @registers) do
    server = start_supervised!({FakeModbusServer, registers})

    start_supervised!(
      {Monitor, name: nil, host: "127.0.0.1", port: FakeModbusServer.port(server)}
    )
  end

  defp context(opts),
    do:
      Map.merge(
        %{task: :solakon_monitor, mode: :phoenix, at: DateTime.utc_now(), config: config()},
        Map.new(opts)
      )

  test "as owner a reading is stored and announced" do
    Ownership.override(%{solakon_monitor: :phoenix, solakon_control: :phoenix})

    assert {:ok, %Reading{id: id}, nil} = MonitorJob.perform(context(monitor: monitor!()))

    reading = Repo.get!(Reading, id)
    assert reading.taken_at == ~U[2026-06-18 10:00:00.000000Z]
    assert reading.active_power_w == 123.0
    assert reading.pv_power_w == 456.0
    assert reading.battery_power_w == -78.0
    assert reading.battery_soc_pct == 55
    assert reading.battery_temperature_c == 42.3
    assert reading.battery_voltage_v == 51.2
    assert reading.battery_current_a == -1.5
    assert reading.inverter_temperature_c == 34.1

    assert {reading.status1, reading.status3, reading.alarm1, reading.alarm2, reading.alarm3} ==
             {4, 0, 0, 8, 0}

    assert {reading.eps_enabled, reading.eps_voltage_v, reading.eps_power_w} ==
             {true, 230.1, 125.0}

    assert_receive {:solakon_reading, ^id}
  end

  test "in shadow mode the reading goes to the shadow database, unannounced", %{repo: repo} do
    Ownership.override(%{solakon_monitor: :shadow})
    Repo.put_writer(:main, :no_main_writer)
    Repo.put_writer(:shadow, repo)

    assert {:ok, %Reading{}, nil} =
             MonitorJob.perform(context(mode: :shadow, monitor: monitor!()))

    assert Repo.aggregate(Reading, :count) == 1
    refute_receive {:solakon_reading, _}
  end

  test "nothing is read without an inverter or with monitoring off" do
    Ownership.override(%{solakon_monitor: :phoenix, solakon_control: :phoenix})
    monitor = monitor!()
    no_inverter = %{config() | solakon: nil}

    MonitorJob.perform(context(config: no_inverter, monitor: monitor))
    MonitorJob.perform(context(config: config("  monitoring_enabled: false"), monitor: monitor))
    SnapshotJob.perform(context(config: no_inverter, monitor: monitor))
    SnapshotJob.perform(context(config: config("  monitoring_enabled: false"), monitor: monitor))

    assert Repo.aggregate(Reading, :count) == 0
    assert Repo.aggregate(Snapshot, :count) == 0
  end

  test "a Modbus failure stores nothing" do
    Ownership.override(%{solakon_monitor: :phoenix, solakon_control: :phoenix})
    monitor = monitor!(Map.delete(@registers, "39424:1"))

    MonitorJob.perform(context(monitor: monitor))

    assert Repo.aggregate(Reading, :count) == 0
    refute_receive {:solakon_reading, _}
  end

  test "a state of charge outside 0..100 is an invalid reading, not a row" do
    Ownership.override(%{solakon_monitor: :phoenix, solakon_control: :phoenix})

    MonitorJob.perform(context(monitor: monitor!(%{@registers | "39424:1" => [0xFFFF]})))

    assert Repo.aggregate(Reading, :count) == 0
  end

  test "a snapshot is stored with its panels and counters" do
    Ownership.override(%{solakon_monitor: :phoenix, solakon_control: :phoenix})

    assert {:ok, %Snapshot{id: id}} = SnapshotJob.perform(context(monitor: monitor!()))

    row = Repo.get!(Snapshot, id)
    assert row.taken_at == ~U[2026-06-18 10:00:00.000000Z]

    assert {row.pv1_power_w, row.pv2_power_w, row.pv1_voltage_v, row.pv1_current_a} ==
             {400.0, 56.0, 41.0, 5.12}

    assert {row.active_power_w, row.battery_power_w, row.battery_health_pct} == {123.0, -78.0, 97}

    assert {row.eps_enabled, row.grid_power_w, row.bms_faults} ==
             {true, 100.0, [0, 0, 0, 0, 0, 0]}

    assert_in_delta row.pv_total_kwh, 123.45, 0.001
    assert row.battery_soc_pct == nil
    refute_receive {:solakon_reading, _}
  end
end
