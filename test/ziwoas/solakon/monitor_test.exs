defmodule Ziwoas.Solakon.MonitorTest do
  # The connection owner: Rails' client tests (test/lib/solakon/client_test.rb) for
  # decoding and error wrapping, plus what a long-lived connection adds — reuse,
  # per-read connections on request, reconnect and backoff — and the writes.
  use ExUnit.Case, async: true

  alias Ziwoas.FakeModbusServer
  alias Ziwoas.Solakon.Monitor

  @fast %{
    "39424:1" => [55],
    "39248:2" => [0x0000, 0x012C],
    "39279:8" => [0, 0x0064, 0, 0x0032, 0, 0, 0, 0],
    "39230:2" => [0xFFFF, 0xFF38],
    "37617:1" => [423],
    "39227:1" => [512],
    "39228:2" => [0, 0],
    "39141:1" => [300],
    "39063:1" => [0],
    "39065:2" => [0, 0],
    "39067:1" => [0],
    "39068:1" => [0],
    "39069:1" => [0],
    "46613:1" => [0],
    "39201:1" => [0],
    "39216:2" => [0, 0]
  }

  defp monitor!(server, opts \\ []) do
    start_supervised!(
      {Monitor,
       [name: nil, host: "127.0.0.1", port: FakeModbusServer.port(server), io_timeout_ms: 500] ++
         opts}
    )
  end

  test "read_state decodes signed values" do
    server = start_supervised!({FakeModbusServer, @fast})

    assert {:ok, state} = Monitor.read_state(monitor!(server))
    assert state.battery_soc == 55
    assert state.active_power_w == 300
    assert state.pv_power_w == 150
    assert state.battery_power_w == -200
    assert_in_delta state.battery_temperature_c, 42.3, 0.001
    assert state.eps_enabled == false
  end

  test "one connection serves every read by default" do
    server = start_supervised!({FakeModbusServer, @fast})
    monitor = monitor!(server)

    assert {:ok, _} = Monitor.read_state(monitor)
    assert {:ok, _} = Monitor.read_state(monitor)
    assert FakeModbusServer.connections(server) == 1
  end

  test "with keep_open: false each read opens and closes its own connection" do
    server = start_supervised!({FakeModbusServer, @fast})
    monitor = monitor!(server, keep_open: false)

    assert {:ok, _} = Monitor.read_state(monitor)
    assert {:ok, _} = Monitor.read_state(monitor)
    assert FakeModbusServer.connections(server) == 2
  end

  test "a dropped idle connection is replaced within the same read" do
    server = start_supervised!({FakeModbusServer, @fast})
    monitor = monitor!(server, keep_open: true)
    assert {:ok, _} = Monitor.read_state(monitor)

    FakeModbusServer.drop_connections(server)

    assert {:ok, %{battery_soc: 55}} = Monitor.read_state(monitor)
    assert FakeModbusServer.connections(server) == 2
  end

  test "a missing register is an error and the next read backs off" do
    server = start_supervised!({FakeModbusServer, Map.delete(@fast, "39141:1")})
    now = :counters.new(1, [])
    monitor = monitor!(server, clock: fn -> :counters.get(now, 1) end)

    assert Monitor.read_state(monitor) == {:error, {:modbus_exception, 2}}
    assert Monitor.read_state(monitor) == {:error, {:backoff, 1_000}}
    requests = length(FakeModbusServer.requests(server))

    :counters.add(now, 1, 1_000)
    assert {:error, {:modbus_exception, 2}} = Monitor.read_state(monitor)
    assert length(FakeModbusServer.requests(server)) > requests

    :counters.add(now, 1, 1_999)
    assert Monitor.read_state(monitor) == {:error, {:backoff, 1}}
  end

  test "an unreachable inverter backs off, doubling to a minute, and recovers" do
    {:ok, listen} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(listen)
    :gen_tcp.close(listen)
    now = :counters.new(1, [])

    monitor =
      start_supervised!(
        {Monitor,
         name: nil,
         host: "127.0.0.1",
         port: port,
         io_timeout_ms: 200,
         clock: fn -> :counters.get(now, 1) end}
      )

    waits =
      for _ <- 1..8 do
        assert {:error, {:connect, :econnrefused}} = Monitor.read_state(monitor)
        {:error, {:backoff, wait}} = Monitor.read_state(monitor)
        :counters.add(now, 1, wait)
        wait
      end

    assert waits == [1_000, 2_000, 4_000, 8_000, 16_000, 32_000, 60_000, 60_000]
  end

  test "read_snapshot reads Rails' snapshot registers" do
    registers =
      Map.merge(@fast, %{
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
      })

    server = start_supervised!({FakeModbusServer, registers})

    assert {:ok, snapshot} = Monitor.read_snapshot(monitor!(server))
    assert [%{index: 1, voltage_v: 41.0, current_a: 5.12, power_w: 0x64} | _] = snapshot.panels
    assert snapshot.grid_power_w == 100
    assert_in_delta snapshot.pv_total_kwh, 123.45, 0.001
    assert snapshot.bms_faults == [0, 0, 0, 0, 0, 0]
    refute Map.has_key?(snapshot, :battery_soc)
  end

  test "writes reach the inverter as FC06/FC16 frames" do
    server = start_supervised!({FakeModbusServer, %{"46609:1" => [10]}})

    assert Monitor.set_eps_output(monitor!(server), true) == :ok
    assert FakeModbusServer.frames(server) == [["0001000000060106b6150002"]]
  end
end
