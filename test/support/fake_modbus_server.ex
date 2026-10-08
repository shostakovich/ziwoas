defmodule Ziwoas.FakeModbusServer do
  @moduledoc false
  use GenServer

  def start_link({registers, opts}), do: GenServer.start_link(__MODULE__, {registers, opts})
  def start_link(registers), do: GenServer.start_link(__MODULE__, {registers, []})

  def child_spec(arg), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}}

  def port(server), do: GenServer.call(server, :port)
  def requests(server), do: GenServer.call(server, :requests)
  def connections(server), do: GenServer.call(server, :connections)
  def drop_connections(server), do: GenServer.call(server, :drop)

  def frames(server), do: GenServer.call(server, :frames)

  def await_connection(server, count \\ 1, timeout \\ 1_000) do
    cond do
      connections(server) >= count -> :ok
      timeout <= 0 -> raise "no connection"
      true -> Process.sleep(5) && await_connection(server, count, timeout - 5)
    end
  end

  @impl true
  def init({registers, opts}) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, packet: :raw])
    server = self()
    acceptor = spawn_link(fn -> accept(listen, server) end)

    {:ok,
     %{
       registers: registers,
       fail: Keyword.get(opts, :fail, []),
       listen: listen,
       acceptor: acceptor,
       requests: [],
       frames: %{},
       connections: 0,
       sockets: []
     }}
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, elem(:inet.port(state.listen), 1), state}
  def handle_call(:requests, _from, state), do: {:reply, Enum.reverse(state.requests), state}
  def handle_call(:connections, _from, state), do: {:reply, state.connections, state}

  def handle_call(:frames, _from, state) do
    frames =
      state.frames |> Enum.sort() |> Enum.map(fn {_n, frames} -> Enum.reverse(frames) end)

    {:reply, frames, state}
  end

  def handle_call(:drop, _from, state) do
    Enum.each(state.sockets, &:gen_tcp.close/1)
    {:reply, :ok, %{state | sockets: []}}
  end

  def handle_call({:connected, socket}, _from, state) do
    number = state.connections + 1

    {:reply, number, %{state | connections: number, sockets: [socket | state.sockets]}}
  end

  def handle_call({:request, connection, frame}, _from, state) do
    <<_header::binary-size(7), function, address::16, rest::binary>> = frame

    state =
      update_in(
        state.frames,
        &Map.update(&1, connection, [hex(frame)], fn f -> [hex(frame) | f] end)
      )

    cond do
      "#{function}:#{address}" in state.fail or "#{function}:*" in state.fail ->
        {:reply, <<function + 0x80, 0x04>>, state}

      function == 0x03 ->
        <<count::16>> = rest
        state = %{state | requests: [{address, count} | state.requests]}
        {:reply, read_reply(Map.get(state.registers, "#{address}:#{count}"), count), state}

      function in [0x06, 0x10] ->
        <<head::binary-size(2), _::binary>> = rest
        {:reply, <<function, address::16, head::binary>>, state}

      true ->
        {:reply, <<function + 0x80, 0x01>>, state}
    end
  end

  defp read_reply(words, count) when is_list(words) and length(words) == count do
    data = for word <- words, into: <<>>, do: <<word::16>>
    <<0x03, byte_size(data), data::binary>>
  end

  defp read_reply(_words, _count), do: <<0x83, 0x02>>

  defp hex(frame), do: Base.encode16(frame, case: :lower)

  defp accept(listen, server) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        pid = spawn(fn -> receive(do: ({:go, number} -> serve(socket, server, number))) end)
        :ok = :gen_tcp.controlling_process(socket, pid)
        number = GenServer.call(server, {:connected, socket})
        send(pid, {:go, number})
        accept(listen, server)

      {:error, _} ->
        :ok
    end
  end

  defp serve(socket, server, number) do
    with {:ok, <<transaction::16, 0::16, length::16, unit>> = header} <-
           :gen_tcp.recv(socket, 7),
         {:ok, pdu} <- :gen_tcp.recv(socket, length - 1) do
      reply = GenServer.call(server, {:request, number, header <> pdu})

      :gen_tcp.send(
        socket,
        <<transaction::16, 0::16, byte_size(reply) + 1::16, unit, reply::binary>>
      )

      serve(socket, server, number)
    else
      _ -> :gen_tcp.close(socket)
    end
  end
end
