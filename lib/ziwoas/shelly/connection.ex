defmodule Ziwoas.Shelly.Connection do
  @moduledoc false
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
    registered_at = System.monotonic_time()
    {:ok, _owner} = Registry.register(Shelly.registry(), plug.id, registered_at)
    replace_older(plug.id, registered_at, args[:peer])
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

  # Two inits can interleave: only the later registration may replace the other.
  defp replace_older(plug_id, registered_at, peer) do
    for {pid, other_at} <- Registry.lookup(Shelly.registry(), plug_id), pid != self() do
      if other_at < registered_at do
        Logger.warning("Shelly #{plug_id}: a connection from #{peer} replaces an older one")
        send(pid, :replaced)
      else
        send(self(), :replaced)
      end
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

  # The relay state is written here, after the plug's answer, so its writes stay in order.
  defp answer({:caller, reply_to, output}, reply, state) do
    state =
      case reply do
        {:ok, _result} when is_boolean(output) ->
          ingest(state, &Ingest.record_output(&1, state.plug, output))

        _other ->
          state
      end

    send(reply_to, {reply_to, reply})
    state
  end

  defguardp metered?(delta) when is_map_key(delta, "apower") or is_map_key(delta, "aenergy")

  # A relay-only delta must not record a sample: it would carry the old watts into this second.
  defp apply_status(state, :merge, %{@component => delta})
       when is_map(delta) and not metered?(delta) do
    state = %{state | switch: Status.merge(state.switch, delta)}

    case delta do
      %{"output" => output} when is_boolean(output) ->
        ingest(state, &Ingest.record_output(&1, state.plug, output))

      _other ->
        state
    end
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
        ingest(state, &Ingest.record(&1, state.plug, reading))

      {:error, :incomplete_status} ->
        if mode == :replace,
          do: Logger.warning("Shelly #{state.plug.id}: status without apower or aenergy.total")

        state
    end
  end

  defp apply_status(state, _mode, _params), do: state

  defp ingest(state, fun) do
    state = %{state | ingest: fun.(state.ingest)}

    if Ingest.pending?(state.ingest) and is_nil(state.flush_timer),
      do: %{state | flush_timer: Process.send_after(self(), :flush, flush_after_ms())},
      else: state
  rescue
    error ->
      Logger.error("Shelly #{state.plug.id}: recording failed: #{Exception.message(error)}")
      state
  end

  defp flush_after_ms, do: Ingest.broadcast_interval_s() * 1_000

  # Sent after its caller gave up, a call would switch a plug already reported as failed.
  @impl true
  def handle_info({:rpc, reply_to, method, params, deadline}, state) do
    if now_ms() < deadline do
      request(state, {:caller, reply_to, switch_output(method, params)}, method, params)
    else
      Logger.warning("Shelly #{state.plug.id}: #{method} dropped, its caller stopped waiting")
      {:ok, state}
    end
  end

  def handle_info(:ping, state) do
    Process.send_after(self(), :ping, @ping_interval_ms)
    {:push, {:ping, ""}, drop_stale_requests(state)}
  end

  def handle_info(:flush, state),
    do: {:ok, %{state | ingest: Ingest.flush(state.ingest), flush_timer: nil}}

  def handle_info(:replaced, state) do
    if Shelly.connection(state.plug.id) == self() do
      {:ok, state}
    else
      # The socket lingers until the peer closes it; no call may reach it meanwhile.
      Registry.unregister(Shelly.registry(), state.plug.id)
      {:stop, :normal, state}
    end
  end

  def handle_info(_message, state), do: {:ok, state}

  defp switch_output("Switch.Set", %{on: on}) when is_boolean(on), do: on
  defp switch_output(_method, _params), do: nil

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
