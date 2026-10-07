defmodule Ziwoas.Solakon.Modbus do
  @moduledoc """
  Modbus TCP on `:gen_tcp`: function code 03 (read holding registers), 06 (write
  single register) and 16 (write multiple registers), which is how the Solakon ONE
  serves every register (`docs/solakon-modbus-protokoll.md` §1). Replaces the
  `rmodbus` gem; the frames are rmodbus' byte for byte (`test/vectors/solakon_modbus_writes.json`).

  A frame is the MBAP header — transaction id, protocol 0, length, unit id — and
  the PDU. Registers are big-endian 16-bit words; the address is the PDU address,
  as rmodbus sends it.

  Every write calls `Ziwoas.Ownership.ensure_owner!(:solakon_control)` right
  before its frame goes on the socket: in `rails`, `shadow` or `dry_run` no write
  frame ever leaves Phoenix.
  """
  alias Ziwoas.Ownership

  @read_holding 0x03
  @write_single 0x06
  @write_multiple 0x10
  @max_registers 125
  @max_write_registers 123

  @type socket :: :gen_tcp.socket()

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

  @spec close(socket | nil) :: :ok
  def close(nil), do: :ok
  def close(socket), do: :gen_tcp.close(socket)

  @doc "The request frame for `count` holding registers from `address`."
  @spec read_request(non_neg_integer, non_neg_integer, non_neg_integer, pos_integer) :: binary
  def read_request(transaction, unit, address, count)
      when count in 1..@max_registers and address in 0..0xFFFF do
    <<transaction::16, 0::16, 6::16, unit::8, @read_holding::8, address::16, count::16>>
  end

  @doc """
  Reads `count` holding registers: `{:ok, [word]}` (unsigned 16-bit) or
  `{:error, reason}` — a Modbus exception reads `{:modbus_exception, code}`.
  """
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

  @doc "The request frame writing `value` into one holding register."
  @spec write_single_request(non_neg_integer, non_neg_integer, non_neg_integer, non_neg_integer) ::
          binary
  def write_single_request(transaction, unit, address, value)
      when address in 0..0xFFFF and value in 0..0xFFFF do
    <<transaction::16, 0::16, 6::16, unit::8, @write_single::8, address::16, value::16>>
  end

  @doc "The request frame writing `values` into consecutive holding registers from `address`."
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

  @doc """
  Writes one holding register (FC06): `:ok` or `{:error, reason}`. Raises
  `Ziwoas.Ownership.NotOwnerError` unless Phoenix owns `solakon_control`.
  """
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

  @doc "Writes consecutive holding registers (FC16); guarded like `write_single_register/6`."
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
    Ownership.ensure_owner!(:solakon_control)

    with :ok <- :gen_tcp.send(socket, frame),
         {:ok, pdu} <- response(socket, transaction, timeout) do
      decode_write_pdu(pdu, function)
    end
  end

  # rmodbus checks neither the echoed address nor the value: any answer with the
  # function code is success, an exception code is the error.
  defp decode_write_pdu(<<function, _rest::binary>>, function), do: :ok

  defp decode_write_pdu(<<exception, code>>, function) when exception == function + 0x80,
    do: {:error, {:modbus_exception, code}}

  defp decode_write_pdu(pdu, _function), do: {:error, {:unexpected_pdu, pdu}}

  # rmodbus 2.1.3 (`TCPSlave#read_pdu`): reads frame after frame until one carries
  # the request's transaction id, skipping late answers to earlier requests; the
  # protocol and unit ids are not checked. `timeout` bounds the whole search.
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

  @doc "The words of a read response PDU."
  @spec decode_pdu(binary, pos_integer) :: {:ok, [non_neg_integer]} | {:error, term}
  def decode_pdu(<<@read_holding, byte_count, data::binary-size(byte_count)>>, count)
      when byte_count == count * 2,
      do: {:ok, for(<<word::16 <- data>>, do: word)}

  def decode_pdu(<<0x83, code>>, _count), do: {:error, {:modbus_exception, code}}
  def decode_pdu(pdu, _count), do: {:error, {:unexpected_pdu, pdu}}

  defp recv(_socket, 0, _timeout), do: {:ok, <<>>}
  defp recv(socket, bytes, timeout), do: :gen_tcp.recv(socket, bytes, timeout)
end
