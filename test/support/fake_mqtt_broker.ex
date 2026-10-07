defmodule Ziwoas.FakeMqttBroker do
  @moduledoc false
  use GenServer

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, [])

  def port(broker), do: GenServer.call(broker, :port)
  def published(broker), do: GenServer.call(broker, :published)
  def subscriptions(broker), do: GenServer.call(broker, :subscriptions)
  def clients(broker), do: GenServer.call(broker, :clients)
  def publish(broker, topic, payload), do: GenServer.call(broker, {:deliver, topic, payload})

  def await(broker, fun, timeout \\ 2_000) do
    cond do
      result = fun.(broker) -> result
      timeout <= 0 -> nil
      true -> Process.sleep(10) && await(broker, fun, timeout - 10)
    end
  end

  @impl true
  def init(_) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, packet: :raw])
    server = self()
    spawn_link(fn -> accept(listen, server) end)
    {:ok, %{listen: listen, sockets: [], published: [], subscriptions: [], clients: []}}
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, elem(:inet.port(state.listen), 1), state}
  def handle_call(:published, _from, state), do: {:reply, Enum.reverse(state.published), state}

  def handle_call(:subscriptions, _from, state),
    do: {:reply, Enum.reverse(state.subscriptions), state}

  def handle_call(:clients, _from, state), do: {:reply, Enum.reverse(state.clients), state}

  def handle_call({:deliver, topic, payload}, _from, state) do
    packet = publish_packet(topic, payload)
    Enum.each(state.sockets, &:gen_tcp.send(&1, packet))
    {:reply, :ok, state}
  end

  def handle_call({:connected, socket, client_id}, _from, state),
    do:
      {:reply, :ok,
       %{state | sockets: [socket | state.sockets], clients: [client_id | state.clients]}}

  def handle_call({:subscribed, filters}, _from, state),
    do: {:reply, :ok, %{state | subscriptions: Enum.reverse(filters) ++ state.subscriptions}}

  def handle_call({:published, message}, _from, state),
    do: {:reply, :ok, %{state | published: [message | state.published]}}

  def handle_call({:closed, socket}, _from, state),
    do: {:reply, :ok, %{state | sockets: List.delete(state.sockets, socket)}}

  defp accept(listen, server) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        pid = spawn(fn -> receive(do: (:go -> serve(socket, server))) end)
        :ok = :gen_tcp.controlling_process(socket, pid)
        send(pid, :go)
        accept(listen, server)

      {:error, _} ->
        :ok
    end
  end

  defp serve(socket, server) do
    case read_packet(socket) do
      {:ok, type, flags, body} ->
        handle_packet(type, flags, body, socket, server)
        serve(socket, server)

      :closed ->
        GenServer.call(server, {:closed, socket})
    end
  end

  defp handle_packet(1, _flags, body, socket, server) do
    <<name_len::16, _name::binary-size(name_len), _level, _connect_flags, _keepalive::16,
      id_len::16, client_id::binary-size(id_len), _rest::binary>> = body

    GenServer.call(server, {:connected, socket, client_id})
    :gen_tcp.send(socket, <<0x20, 2, 0, 0>>)
  end

  defp handle_packet(8, _flags, <<packet_id::16, rest::binary>>, socket, server) do
    filters = for <<len::16, filter::binary-size(len), _qos <- rest>>, do: filter
    GenServer.call(server, {:subscribed, filters})
    acks = :binary.copy(<<0>>, length(filters))
    :gen_tcp.send(socket, <<0x90, 2 + length(filters), packet_id::16, acks::binary>>)
  end

  defp handle_packet(
         3,
         flags,
         <<len::16, topic::binary-size(len), payload::binary>>,
         _socket,
         server
       ) do
    GenServer.call(
      server,
      {:published, %{topic: topic, payload: payload, retain: Bitwise.band(flags, 1) == 1}}
    )
  end

  defp handle_packet(12, _flags, _body, socket, _server), do: :gen_tcp.send(socket, <<0xD0, 0>>)
  defp handle_packet(_type, _flags, _body, _socket, _server), do: :ok

  defp read_packet(socket) do
    with {:ok, <<type::4, flags::4>>} <- :gen_tcp.recv(socket, 1),
         {:ok, length} <- read_length(socket, 0, 1),
         {:ok, body} <- recv(socket, length) do
      {:ok, type, flags, body}
    else
      _ -> :closed
    end
  end

  defp read_length(socket, value, multiplier) do
    case :gen_tcp.recv(socket, 1) do
      {:ok, <<1::1, digit::7>>} ->
        read_length(socket, value + digit * multiplier, multiplier * 128)

      {:ok, <<0::1, digit::7>>} ->
        {:ok, value + digit * multiplier}

      error ->
        error
    end
  end

  defp recv(_socket, 0), do: {:ok, <<>>}
  defp recv(socket, length), do: :gen_tcp.recv(socket, length)

  defp publish_packet(topic, payload) do
    body = <<byte_size(topic)::16, topic::binary, payload::binary>>
    <<0x30, encode_length(byte_size(body))::binary, body::binary>>
  end

  defp encode_length(length) when length < 128, do: <<length>>

  defp encode_length(length),
    do: <<1::1, rem(length, 128)::7, encode_length(div(length, 128))::binary>>
end
