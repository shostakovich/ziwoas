defmodule Ziwoas.FakeShelly do
  @moduledoc false

  # The registry is global: only for tests that do not run async.
  @spec serve(String.t(), (String.t(), map -> {:ok, term} | {:error, term})) :: pid
  def serve(plug_id, answer \\ fn _method, _params -> {:ok, %{"was_on" => false}} end) do
    test = self()
    ready = make_ref()

    pid =
      spawn_link(fn ->
        {:ok, _owner} =
          Registry.register(Ziwoas.Shelly.registry(), plug_id, System.monotonic_time())

        send(test, ready)
        loop(plug_id, test, answer)
      end)

    receive do
      ^ready -> pid
    end
  end

  defp loop(plug_id, test, answer) do
    receive do
      {:rpc, reply_to, method, params} ->
        send(test, {:shelly_rpc, plug_id, method, params})
        send(reply_to, {reply_to, answer.(method, params)})
        loop(plug_id, test, answer)
    end
  end
end

defmodule Ziwoas.FakeShellyDevice do
  @moduledoc false
  use GenServer

  @src "shellyplugsg3-test"

  def start_link(opts), do: GenServer.start_link(__MODULE__, Keyword.put_new(opts, :test, self()))

  def child_spec(opts),
    do: %{id: {__MODULE__, opts[:plug_id]}, start: {__MODULE__, :start_link, [opts]}}

  def notify(device, frame), do: GenServer.call(device, {:send, frame})

  @spec handshake(:inet.port_number(), String.t()) ::
          {:ok, :gen_tcp.socket(), binary} | {:error, integer}
  def handshake(port, path) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    key = Base.encode64(:crypto.strong_rand_bytes(16))

    :ok =
      :gen_tcp.send(socket, [
        "GET #{path} HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n",
        "Connection: Upgrade\r\nSec-WebSocket-Key: #{key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
      ])

    {head, rest} = read_head(socket, "")
    [_version, status | _reason] = String.split(head, " ", parts: 3)

    case String.to_integer(status) do
      101 ->
        {:ok, socket, rest}

      other ->
        :gen_tcp.close(socket)
        {:error, other}
    end
  end

  defp read_head(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [head, rest] ->
        {head, rest}

      [_partial] ->
        {:ok, data} = :gen_tcp.recv(socket, 0, 1_000)
        read_head(socket, buffer <> data)
    end
  end

  @impl true
  def init(opts) do
    plug_id = Keyword.fetch!(opts, :plug_id)

    case handshake(Keyword.fetch!(opts, :port), "/shelly/#{plug_id}") do
      {:ok, socket, rest} ->
        :ok = :inet.setopts(socket, active: true)

        state = %{
          socket: socket,
          plug_id: plug_id,
          test: opts[:test],
          answer: Keyword.get(opts, :answer, &default_answer/2),
          buffer: ""
        }

        {:ok, receive_frames(state, rest)}

      {:error, status} ->
        {:stop, {:handshake, status}}
    end
  end

  defp default_answer("Switch.Set", _params), do: {:ok, %{"was_on" => false}}
  defp default_answer(_method, _params), do: {:ok, %{}}

  @impl true
  def handle_call({:send, frame}, _from, state) do
    {:reply, send_frame(state.socket, 0x1, JSON.encode!(frame)), state}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state), do: {:noreply, receive_frames(state, data)}
  def handle_info({:tcp_closed, _socket}, state), do: {:stop, :normal, state}

  defp receive_frames(state, data) do
    case parse(state.buffer <> data) do
      {:ok, opcode, payload, rest} ->
        handle_frame(opcode, payload, state)
        receive_frames(%{state | buffer: ""}, rest)

      :more ->
        %{state | buffer: state.buffer <> data}
    end
  end

  defp handle_frame(0x1, text, state) do
    case JSON.decode!(text) do
      %{"id" => id, "src" => src, "method" => method} = request ->
        params = Map.get(request, "params", %{})
        send(state.test, {:shelly_request, state.plug_id, method, params})

        reply =
          case state.answer.(method, params) do
            {:ok, result} -> %{result: result}
            {:error, code, message} -> %{error: %{code: code, message: message}}
          end

        frame = Map.merge(%{id: id, src: @src, dst: src}, reply)
        send_frame(state.socket, 0x1, JSON.encode!(frame))

      _other ->
        :ok
    end
  end

  defp handle_frame(0x9, payload, state), do: send_frame(state.socket, 0xA, payload)
  defp handle_frame(_opcode, _payload, _state), do: :ok

  # Server frames are unmasked.
  defp parse(<<_::4, opcode::4, 0::1, 126::7, len::16, payload::binary-size(len), rest::binary>>),
    do: {:ok, opcode, payload, rest}

  defp parse(<<_::4, opcode::4, 0::1, 127::7, len::64, payload::binary-size(len), rest::binary>>),
    do: {:ok, opcode, payload, rest}

  defp parse(<<_::4, opcode::4, 0::1, len::7, payload::binary-size(len), rest::binary>>)
       when len < 126,
       do: {:ok, opcode, payload, rest}

  defp parse(_incomplete), do: :more

  defp send_frame(socket, opcode, payload) do
    mask = :crypto.strong_rand_bytes(4)
    size = byte_size(payload)

    head = <<1::1, 0::3, opcode::4, 1::1>>

    header =
      cond do
        size < 126 -> <<head::bitstring, size::7>>
        size < 65_536 -> <<head::bitstring, 126::7, size::16>>
        true -> <<head::bitstring, 127::7, size::64>>
      end

    pad = binary_part(:binary.copy(mask, div(size, 4) + 1), 0, size)
    :gen_tcp.send(socket, [header, mask, :crypto.exor(payload, pad)])
  end
end
