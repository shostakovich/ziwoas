defmodule Ziwoas.Solakon.MonitorJobTest do
  # Subscribes to a global PubSub topic another test broadcasts on.
  use Ziwoas.DataCase

  alias Ziwoas.{Config, FakeModbusServer, Repo, TestClock}
  alias Ziwoas.Solakon.Control.{Decision, Outcome, State}
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

  setup do
    TestClock.freeze(@now)
    Ziwoas.Solakon.subscribe()
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "solakon")
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

  defp monitor!(registers \\ @registers), do: registers |> inverter!() |> elem(1)

  defp inverter!(registers, opts \\ []) do
    server = start_supervised!({FakeModbusServer, {registers, opts}})

    monitor =
      start_supervised!(
        {Monitor, name: nil, host: "127.0.0.1", port: FakeModbusServer.port(server)}
      )

    {server, monitor}
  end

  defp writes(server) do
    for frame <- List.flatten(FakeModbusServer.frames(server)),
        String.slice(frame, 14, 2) in ["06", "10"],
        do: String.slice(frame, 4..-1//1)
  end

  defp context(opts), do: Keyword.merge([config: config(), at: DateTime.utc_now()], opts)

  test "a reading is stored and announced" do
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

    assert_receive {:reading, %Reading{id: ^id}}
    assert_receive {:solakon_reading, ^id}
  end

  test "a Modbus failure stores nothing" do
    monitor = monitor!(Map.delete(@registers, "39424:1"))

    MonitorJob.perform(context(monitor: monitor))

    assert Repo.aggregate(Reading, :count) == 0
    refute_receive {:solakon_reading, _}
  end

  test "a state of charge outside 0..100 is an invalid reading, not a row" do
    MonitorJob.perform(context(monitor: monitor!(%{@registers | "39424:1" => [0xFFFF]})))

    assert Repo.aggregate(Reading, :count) == 0
  end

  test "a snapshot is stored with its panels and counters" do
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

  describe "with control enabled" do
    @controlled Map.put(@registers, "46609:1", [10])

    defp controlled, do: context(config: config("  control_enabled: true"))

    test "the stored reading is regulated: the target goes out, the decision is kept" do
      {server, monitor} = inverter!(@controlled)

      assert {:ok, %Reading{id: id}, %Outcome{status: :applied, decision: decision}} =
               MonitorJob.perform(Keyword.put(controlled(), :monitor, monitor))

      # No consumer plugs configured: no load, no floor.
      assert decision == %Decision{state: :normal, target_w: 0, trim: false}
      assert List.last(writes(server)) == "0000000b0110b3b300020400000000"
      assert {^decision, _at} = State.stored(State.current())
      assert_receive {:solakon_reading, ^id}
    end

    test "a refused write keeps the reading and its announcement, and counts the failure" do
      {_server, monitor} = inverter!(@controlled, fail: ["16:46003"])

      assert {:ok, %Reading{id: id}, %Outcome{status: :failed, failures: 1}} =
               MonitorJob.perform(Keyword.put(controlled(), :monitor, monitor))

      assert Repo.aggregate(Reading, :count) == 1
      assert_receive {:solakon_reading, ^id}
      assert State.current().consecutive_failures == 1
    end

    test "the third refused write in a row hands control back" do
      {server, monitor} = inverter!(@controlled, fail: ["16:46003"])
      context = Keyword.put(controlled(), :monitor, monitor)

      outcomes = for _ <- 1..3, do: context |> MonitorJob.perform() |> elem(2)

      assert Enum.map(outcomes, &{&1.status, &1.failures}) ==
               [failed: 1, failed: 2, released: 3]

      assert List.last(writes(server)) == "000000060106b3b10000"
      assert State.current().consecutive_failures == 0
      assert Repo.aggregate(Reading, :count) == 3
    end

    test "a failed read stores nothing and writes nothing" do
      {server, monitor} = inverter!(Map.delete(@controlled, "39424:1"))

      assert {:error, {:modbus_exception, 2}} =
               MonitorJob.perform(Keyword.put(controlled(), :monitor, monitor))

      assert writes(server) == []
      assert Repo.aggregate(State, :count) == 0
    end

    test "an invalid reading is not regulated" do
      {server, monitor} = inverter!(%{@controlled | "39424:1" => [0xFFFF]})

      assert {:error, %Ecto.Changeset{}} =
               MonitorJob.perform(Keyword.put(controlled(), :monitor, monitor))

      assert writes(server) == []
    end
  end

  test "with control off nothing is written" do
    {server, monitor} = inverter!(Map.put(@registers, "46609:1", [10]))

    assert {:ok, _reading, nil} = MonitorJob.perform(context(monitor: monitor))
    assert writes(server) == []
  end
end
