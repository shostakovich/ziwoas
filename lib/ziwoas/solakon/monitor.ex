defmodule Ziwoas.Solakon.Monitor do
  @moduledoc "A failed reused connection is retried once: the inverter drops idle clients and every write sets an absolute value."
  use GenServer

  require Logger

  alias Ziwoas.Solakon.{Client, Modbus}

  @min_backoff_ms 1_000
  @max_backoff_ms 60_000
  @io_timeout_ms 5_000
  @call_timeout_ms 120_000
  @reads [:state, :snapshot]

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @spec read_state(GenServer.server()) :: {:ok, map} | {:error, term}
  def read_state(server \\ __MODULE__), do: request(server, :state)

  @spec read_snapshot(GenServer.server()) :: {:ok, map} | {:error, term}
  def read_snapshot(server \\ __MODULE__), do: request(server, :snapshot)

  @spec apply_control(GenServer.server(), integer, integer) :: :ok | {:error, term}
  def apply_control(server \\ __MODULE__, power_w, min_soc),
    do: request(server, {:apply_control, power_w, min_soc})

  @spec release_control(GenServer.server()) :: :ok | {:error, term}
  def release_control(server \\ __MODULE__), do: request(server, :release_control)

  @spec set_eps_output(GenServer.server(), boolean | nil) :: :ok | {:error, term}
  def set_eps_output(server \\ __MODULE__, enabled),
    do: request(server, {:set_eps_output, enabled})

  defp request(server, operation),
    do: GenServer.call(server, {:request, operation}, @call_timeout_ms)

  @impl true
  def init(opts) do
    state = %{
      host: Keyword.fetch!(opts, :host),
      port: Keyword.get(opts, :port, 502),
      unit: Keyword.get(opts, :unit_id, 1),
      keep_open: Keyword.get(opts, :keep_open, true),
      io_timeout: Keyword.get(opts, :io_timeout_ms, @io_timeout_ms),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      conn: nil,
      backoff: nil,
      retry_at: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:request, operation}, _from, state) do
    now = state.clock.()

    # Release must not wait out a backoff: it follows failed writes, often the backoff's cause.
    if (operation != :release_control and state.retry_at) && now < state.retry_at do
      {:reply, {:error, {:backoff, state.retry_at - now}}, state}
    else
      {reply, state} = perform(operation, state)
      {:reply, reply, state}
    end
  end

  defp perform(operation, state) do
    reused = not is_nil(state.conn)

    case attempt(operation, state) do
      # The inverter refused: no retry and no backoff.
      {{:error, {:modbus_exception, _}} = error, state} when operation not in @reads ->
        Logger.warning("Solakon.Monitor: #{inspect(elem(error, 1))}")
        {error, state}

      {{:error, _}, state} when reused ->
        perform(operation, state)

      {{:error, reason} = error, state} ->
        Logger.warning("Solakon.Monitor: #{inspect(reason)}")
        {error, back_off(state)}

      {result, state} ->
        {result, %{state | backoff: nil, retry_at: nil} |> release()}
    end
  end

  defp attempt(operation, state) do
    with {:ok, state} <- ensure_conn(state) do
      case operate(operation, state.conn) do
        {:ok, value, conn} -> {{:ok, value}, %{state | conn: conn}}
        {:ok, conn} -> {:ok, %{state | conn: conn}}
        {:error, _} = error -> {error, close(state)}
      end
    end
  end

  defp operate(:state, conn), do: Client.read_state(conn)
  defp operate(:snapshot, conn), do: Client.read_snapshot(conn)

  defp operate({:apply_control, power_w, min_soc}, conn),
    do: Client.apply_control(conn, power_w, min_soc)

  defp operate(:release_control, conn), do: Client.release_control(conn)
  defp operate({:set_eps_output, enabled}, conn), do: Client.set_eps_output(conn, enabled)

  defp ensure_conn(%{conn: nil} = state) do
    case Modbus.open(state.host, state.port, state.unit, state.io_timeout) do
      {:ok, conn} -> {:ok, %{state | conn: conn}}
      {:error, reason} -> {{:error, {:connect, reason}}, state}
    end
  end

  defp ensure_conn(state), do: {:ok, state}

  defp release(%{keep_open: true} = state), do: state
  defp release(state), do: close(state)

  defp close(state) do
    Modbus.close(state.conn)
    %{state | conn: nil}
  end

  defp back_off(state) do
    backoff = if state.backoff, do: min(state.backoff * 2, @max_backoff_ms), else: @min_backoff_ms
    %{close(state) | backoff: backoff, retry_at: state.clock.() + backoff}
  end

  @impl true
  def terminate(_reason, state), do: Modbus.close(state.conn)
end
