defmodule Ziwoas.Solakon.Modbus do
  @moduledoc false
  @read_holding 0x03
  @write_single 0x06
  @write_multiple 0x10
  @max_registers 125
  @max_write_registers 123

  @enforce_keys [:socket, :unit, :timeout]
  defstruct [:socket, :unit, :timeout, transaction: 0]

  @type socket :: :gen_tcp.socket()
  @type t :: %__MODULE__{
          socket: socket,
          unit: non_neg_integer,
          timeout: timeout,
          transaction: non_neg_integer
        }
  @type write_op ::
          {:single, non_neg_integer, non_neg_integer}
          | {:multiple, non_neg_integer, [non_neg_integer]}

  @spec open(String.t() | charlist, :inet.port_number(), non_neg_integer, timeout) ::
          {:ok, t} | {:error, term}
  def open(host, port, unit, timeout) do
    with {:ok, socket} <- connect(host, port, timeout),
         do: {:ok, %__MODULE__{socket: socket, unit: unit, timeout: timeout}}
  end

  @spec read(t, non_neg_integer, pos_integer) :: {:ok, [non_neg_integer], t} | {:error, term}
  def read(%__MODULE__{} = conn, address, count) do
    conn = next_transaction(conn)

    with {:ok, words} <-
           read_holding_registers(
             conn.socket,
             conn.transaction,
             conn.unit,
             address,
             count,
             conn.timeout
           ),
         do: {:ok, words, conn}
  end

  @spec write(t, write_op) :: {:ok, t} | {:error, term}
  def write(%__MODULE__{} = conn, operation) do
    conn = next_transaction(conn)

    result =
      case operation do
        {:single, address, value} ->
          write_single_register(
            conn.socket,
            conn.transaction,
            conn.unit,
            address,
            value,
            conn.timeout
          )

        {:multiple, address, values} ->
          write_multiple_registers(
            conn.socket,
            conn.transaction,
            conn.unit,
            address,
            values,
            conn.timeout
          )
      end

    with :ok <- result, do: {:ok, conn}
  end

  defp next_transaction(%__MODULE__{transaction: id} = conn),
    do: %{conn | transaction: rem(id, 0xFFFF) + 1}

  @spec connect(String.t() | charlist, :inet.port_number(), timeout) ::
          {:ok, socket} | {:error, term}
  def connect(host, port, timeout),
    do:
      :gen_tcp.connect(
        to_charlist(host),
        port,
        [:binary, active: false, packet: :raw, nodelay: true],
        timeout
      )

  @spec close(t | socket | nil) :: :ok
  def close(nil), do: :ok
  def close(%__MODULE__{socket: socket}), do: :gen_tcp.close(socket)
  def close(socket), do: :gen_tcp.close(socket)

  @spec read_request(non_neg_integer, non_neg_integer, non_neg_integer, pos_integer) :: binary
  def read_request(transaction, unit, address, count)
      when count in 1..@max_registers and address in 0..0xFFFF do
    <<transaction::16, 0::16, 6::16, unit::8, @read_holding::8, address::16, count::16>>
  end

  @spec read_holding_registers(
          socket,
          non_neg_integer,
          non_neg_integer,
          non_neg_integer,
          pos_integer,
          timeout
        ) ::
          {:ok, [non_neg_integer]} | {:error, term}
  def read_holding_registers(socket, transaction, unit, address, count, timeout) do
    with :ok <- :gen_tcp.send(socket, read_request(transaction, unit, address, count)),
         {:ok, pdu} <- response(socket, transaction, timeout) do
      decode_pdu(pdu, count)
    end
  end

  @spec write_single_request(non_neg_integer, non_neg_integer, non_neg_integer, non_neg_integer) ::
          binary
  def write_single_request(transaction, unit, address, value)
      when address in 0..0xFFFF and value in 0..0xFFFF do
    <<transaction::16, 0::16, 6::16, unit::8, @write_single::8, address::16, value::16>>
  end

  @spec write_multiple_request(non_neg_integer, non_neg_integer, non_neg_integer, [
          non_neg_integer
        ]) :: binary
  def write_multiple_request(transaction, unit, address, values)
      when length(values) in 1..@max_write_registers and address in 0..0xFFFF do
    data = for value when value in 0..0xFFFF <- values, into: <<>>, do: <<value::16>>
    count = length(values)
    if byte_size(data) != count * 2, do: raise(ArgumentError, "words must be 0..0xFFFF")

    <<transaction::16, 0::16, 7 + count * 2::16, unit::8, @write_multiple::8, address::16,
      count::16, count * 2::8, data::binary>>
  end

  @spec write_single_register(
          socket,
          non_neg_integer,
          non_neg_integer,
          non_neg_integer,
          non_neg_integer,
          timeout
        ) :: :ok | {:error, term}
  def write_single_register(socket, transaction, unit, address, value, timeout) do
    frame = write_single_request(transaction, unit, address, value)
    write(socket, frame, transaction, timeout, @write_single)
  end

  @spec write_multiple_registers(
          socket,
          non_neg_integer,
          non_neg_integer,
          non_neg_integer,
          [non_neg_integer],
          timeout
        ) :: :ok | {:error, term}
  def write_multiple_registers(socket, transaction, unit, address, values, timeout) do
    frame = write_multiple_request(transaction, unit, address, values)
    write(socket, frame, transaction, timeout, @write_multiple)
  end

  defp write(socket, frame, transaction, timeout, function) do
    with :ok <- :gen_tcp.send(socket, frame),
         {:ok, pdu} <- response(socket, transaction, timeout) do
      decode_write_pdu(pdu, function)
    end
  end

  defp decode_write_pdu(<<function, _rest::binary>>, function), do: :ok

  defp decode_write_pdu(<<exception, code>>, function) when exception == function + 0x80,
    do: {:error, {:modbus_exception, code}}

  defp decode_write_pdu(pdu, _function), do: {:error, {:unexpected_pdu, pdu}}

  # Skips late answers to earlier requests.
  defp response(socket, transaction, timeout),
    do: read_response(socket, transaction, System.monotonic_time(:millisecond) + timeout)

  defp read_response(socket, transaction, deadline) do
    with {:ok, <<id::16, _protocol::16, length::16, _unit::8>>} <-
           recv(socket, 7, remaining(deadline)),
         true <- length in 2..254 || {:error, {:bad_length, length}},
         {:ok, pdu} <- recv(socket, length - 1, remaining(deadline)) do
      if id == transaction, do: {:ok, pdu}, else: read_response(socket, transaction, deadline)
    end
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  @spec decode_pdu(binary, pos_integer) :: {:ok, [non_neg_integer]} | {:error, term}
  def decode_pdu(<<@read_holding, byte_count, data::binary-size(byte_count)>>, count)
      when byte_count == count * 2,
      do: {:ok, for(<<word::16 <- data>>, do: word)}

  def decode_pdu(<<0x83, code>>, _count), do: {:error, {:modbus_exception, code}}
  def decode_pdu(pdu, _count), do: {:error, {:unexpected_pdu, pdu}}

  defp recv(_socket, 0, _timeout), do: {:ok, <<>>}
  defp recv(socket, bytes, timeout), do: :gen_tcp.recv(socket, bytes, timeout)
end
