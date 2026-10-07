defmodule Ziwoas.Shelly.Connection do
  @moduledoc """
  One Shelly's outbound websocket (`WebSock`, under `Ziwoas.Shelly.Listener`),
  speaking the device's JSON-RPC.

  - It keeps the device's `switch:0` status: a full status (`NotifyFullStatus`, the
    `Shelly.GetStatus` it asks for on connect) replaces it, a `NotifyStatus` delta is
    merged in (`Ziwoas.Shelly.Status`). Every frame that touches `switch:0` hands the
    status to `Ziwoas.Plugs.Ingest`.
  - `{:rpc, reply_to, method, params}` (`Ziwoas.Shelly.call/4`) goes out as a request;
    the answer goes to `reply_to` as `{reply_to, {:ok, result} | {:error, reason}}`.
  - A newer connection for the same plug replaces this one.

  Anything it cannot read is logged and dropped; a failing database write does not
  close the connection.
  """
  @behaviour WebSock

  require Logger

  alias Ziwoas.Plugs.Ingest
  alias Ziwoas.Shelly
  alias Ziwoas.Shelly.Status

  @component "switch:0"
  @src "ziwoas"
  @ping_interval_ms 30_000
  @request_ttl_ms 30_000

  @impl true
  def init(%{plug: plug} = args) do
    {:ok, _owner} = Registry.register(Shelly.registry(), plug.id, System.monotonic_time())
    replace_older(plug.id, args[:peer])
    Process.send_after(self(), :ping, @ping_interval_ms)

    state = %{
      plug: plug,
      peer: args[:peer],
      ingest: Ingest.new(Map.get(args, :ingest, [])),
      switch: %{},
      next_id: 1,
      requests: %{},
      flush_timer: nil
    }

    Logger.info("Shelly #{plug.id}: connected from #{state.peer}")
    request(state, :get_status, "Shelly.GetStatus", %{})
  end

  defp replace_older(plug_id, peer) do
    for {pid, _registered_at} <- Registry.lookup(Shelly.registry(), plug_id), pid != self() do
      Logger.warning("Shelly #{plug_id}: a connection from #{peer} replaces an older one")
      send(pid, :replaced)
    end
  end

  @impl true
  def handle_in({text, opcode: :text}, state) do
    case JSON.decode(text) do
      {:ok, frame} when is_map(frame) ->
        {:ok, handle_frame(frame, state)}

      _other ->
        Logger.warning("Shelly #{state.plug.id}: invalid JSON frame")
        {:ok, state}
    end
  end

  def handle_in(_binary, state), do: {:ok, state}

  defp handle_frame(%{"method" => "NotifyFullStatus", "params" => params}, state),
    do: apply_status(state, :replace, params)

  defp handle_frame(%{"method" => "NotifyStatus", "params" => params}, state),
    do: apply_status(state, :merge, params)

  defp handle_frame(%{"method" => _event}, state), do: state

  defp handle_frame(%{"id" => id} = frame, state) when is_map_key(state.requests, id) do
    {{kind, _sent_at}, requests} = Map.pop(state.requests, id)
    answer(kind, response(frame), %{state | requests: requests})
  end

  defp handle_frame(_frame, state), do: state

  defp response(%{"result" => result}), do: {:ok, result}

  defp response(%{"error" => %{"code" => code, "message" => message}}),
    do: {:error, {:rpc, code, message}}

  defp response(_frame), do: {:error, {:rpc, nil, "malformed response"}}

  defp answer(:get_status, {:ok, result}, state), do: apply_status(state, :replace, result)

  defp answer(:get_status, {:error, reason}, state) do
    Logger.warning("Shelly #{state.plug.id}: Shelly.GetStatus failed: #{inspect(reason)}")
    state
  end

  defp answer({:caller, reply_to}, reply, state) do
    send(reply_to, {reply_to, reply})
    state
  end

  defp apply_status(state, mode, %{@component => switch}) when is_map(switch) do
    status =
      case mode do
        :replace -> Status.replace(switch)
        :merge -> Status.merge(state.switch, switch)
      end

    state = %{state | switch: status}

    case Status.reading(status) do
      {:ok, reading} ->
        record(state, reading)

      {:error, :incomplete_status} ->
        if mode == :replace,
          do: Logger.warning("Shelly #{state.plug.id}: status without apower or aenergy.total")

        state
    end
  end

  defp apply_status(state, _mode, _params), do: state

  defp record(state, reading) do
    state = %{state | ingest: Ingest.record(state.ingest, state.plug, reading)}

    if Ingest.pending?(state.ingest) and is_nil(state.flush_timer),
      do: %{state | flush_timer: Process.send_after(self(), :flush, flush_after_ms())},
      else: state
  rescue
    error ->
      Logger.error("Shelly #{state.plug.id}: recording failed: #{Exception.message(error)}")
      state
  end

  defp flush_after_ms, do: Ingest.broadcast_interval_s() * 1_000

  @impl true
  def handle_info({:rpc, reply_to, method, params}, state),
    do: request(state, {:caller, reply_to}, method, params)

  def handle_info(:ping, state) do
    Process.send_after(self(), :ping, @ping_interval_ms)
    {:push, {:ping, ""}, drop_stale_requests(state)}
  end

  def handle_info(:flush, state),
    do: {:ok, %{state | ingest: Ingest.flush(state.ingest), flush_timer: nil}}

  def handle_info(:replaced, state), do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(reason, state) do
    Logger.info("Shelly #{state.plug.id}: disconnected (#{inspect(reason)})")
    :ok
  end

  defp request(state, kind, method, params) do
    id = state.next_id
    frame = JSON.encode!(%{id: id, src: @src, method: method, params: params})
    requests = Map.put(state.requests, id, {kind, now_ms()})
    {:push, {:text, frame}, %{state | next_id: id + 1, requests: requests}}
  end

  # A caller stops waiting after its timeout; its unanswered request goes too.
  defp drop_stale_requests(state) do
    cutoff = now_ms() - @request_ttl_ms

    %{
      state
      | requests: Map.reject(state.requests, fn {_id, {_kind, sent_at}} -> sent_at < cutoff end)
    }
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
