defmodule Ziwoas.Solakon.ModbusTest do
  use ExUnit.Case, async: true

  alias Ziwoas.FakeModbusServer
  alias Ziwoas.Solakon.Modbus

  test "a read request is the MBAP header and an FC03 PDU" do
    assert Modbus.read_request(0x0102, 1, 39424, 2) ==
             <<0x01, 0x02, 0, 0, 0, 6, 1, 0x03, 39424::16, 0, 2>>
  end

  test "write requests are FC06 and FC16 frames" do
    assert Base.encode16(Modbus.write_single_request(2, 1, 46001, 1), case: :lower) ==
             "0002000000060106b3b10001"

    assert Base.encode16(Modbus.write_multiple_request(4, 1, 46003, [0xFFFF, 0xFFB5]),
             case: :lower
           ) ==
             "00040000000b0110b3b3000204ffffffb5"

    assert_raise ArgumentError, fn -> Modbus.write_multiple_request(1, 1, 46003, [0x10000]) end
    assert_raise FunctionClauseError, fn -> Modbus.write_single_request(1, 1, 46001, -1) end
  end

  test "requests stay within one PDU and the address space" do
    assert_raise FunctionClauseError, fn -> Modbus.read_request(1, 1, 0, 126) end
    assert_raise FunctionClauseError, fn -> Modbus.read_request(1, 1, 0x10000, 1) end
  end

  test "a response PDU decodes into unsigned words, an exception into its code" do
    assert Modbus.decode_pdu(<<0x03, 4, 0xFF, 0xFF, 0x01, 0x2C>>, 2) == {:ok, [0xFFFF, 300]}
    assert Modbus.decode_pdu(<<0x83, 0x02>>, 2) == {:error, {:modbus_exception, 2}}
    assert {:error, {:unexpected_pdu, _}} = Modbus.decode_pdu(<<0x03, 2, 0, 1>>, 2)
  end

  test "reads holding registers over TCP" do
    server = start_supervised!({FakeModbusServer, %{"39248:2" => [0, 300]}})
    {:ok, socket} = Modbus.connect("127.0.0.1", FakeModbusServer.port(server), 1_000)

    assert Modbus.read_holding_registers(socket, 7, 1, 39248, 2, 1_000) == {:ok, [0, 300]}

    assert Modbus.read_holding_registers(socket, 8, 1, 1, 1, 1_000) ==
             {:error, {:modbus_exception, 2}}

    assert FakeModbusServer.requests(server) == [{39248, 2}, {1, 1}]
    Modbus.close(socket)
  end

  # A server that answers each request with `frames.(request)`, raw bytes.
  defp raw_server(frames) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])

    server =
      spawn_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listen)
        serve(socket, frames)
      end)

    on_exit(fn -> Process.exit(server, :kill) end)
    {:ok, port} = :inet.port(listen)
    port
  end

  defp serve(socket, frames) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, request} ->
        :ok = :gen_tcp.send(socket, frames.(request))
        serve(socket, frames)

      {:error, _} ->
        :ok
    end
  end

  defp frame(transaction, unit, pdu),
    do: <<transaction::16, 0::16, byte_size(pdu) + 1::16, unit::8, pdu::binary>>

  test "a late answer to an earlier request is skipped and the unit id ignored" do
    port =
      raw_server(fn <<transaction::16, _::binary>> ->
        frame(transaction - 1, 1, <<0x03, 2, 0, 99>>) <>
          frame(transaction, 0xFF, <<0x03, 2, 1, 44>>)
      end)

    {:ok, socket} = Modbus.connect("127.0.0.1", port, 1_000)

    assert Modbus.read_holding_registers(socket, 7, 1, 39248, 1, 1_000) == {:ok, [300]}
    Modbus.close(socket)
  end

  test "a write's answer is found past a stale frame too" do
    port =
      raw_server(fn <<transaction::16, _::binary-size(5), pdu::binary>> ->
        frame(transaction + 5, 1, <<0x83, 0x02>>) <> frame(transaction, 3, pdu)
      end)

    {:ok, socket} = Modbus.connect("127.0.0.1", port, 1_000)

    assert Modbus.write_single_register(socket, 2, 1, 46001, 1, 1_000) == :ok
    Modbus.close(socket)
  end

  test "only foreign transaction ids time out within the request's timeout" do
    port = raw_server(fn _ -> frame(4242, 1, <<0x03, 2, 0, 1>>) end)
    {:ok, socket} = Modbus.connect("127.0.0.1", port, 1_000)
    started = System.monotonic_time(:millisecond)

    assert Modbus.read_holding_registers(socket, 1, 1, 1, 1, 200) == {:error, :timeout}
    assert System.monotonic_time(:millisecond) - started < 1_000
    Modbus.close(socket)
  end

  test "a closed connection is an error, not a crash" do
    server = start_supervised!({FakeModbusServer, %{}})
    {:ok, socket} = Modbus.connect("127.0.0.1", FakeModbusServer.port(server), 1_000)
    FakeModbusServer.await_connection(server)
    FakeModbusServer.drop_connections(server)

    assert {:error, _} = Modbus.read_holding_registers(socket, 1, 1, 1, 1, 500)
  end
end
