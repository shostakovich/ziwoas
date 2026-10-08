defmodule Ziwoas.Shelly.Server do
  @moduledoc false
  use GenServer

  require Logger

  @retry_min_ms 1_000
  @retry_max_ms 60_000

  def start_link(bandit_opts), do: GenServer.start_link(__MODULE__, bandit_opts)

  @spec port(GenServer.server()) :: :inet.port_number() | nil
  def port(server), do: GenServer.call(server, :port)

  # A port in use must not fail the start: the Collector, and with it the web UI, would go down.
  @impl true
  def init(bandit_opts) do
    Process.flag(:trap_exit, true)
    {:ok, listen(%{opts: bandit_opts, bandit: nil, retry_ms: @retry_min_ms})}
  end

  @impl true
  def handle_call(:port, _from, %{bandit: nil} = state), do: {:reply, nil, state}

  def handle_call(:port, _from, state) do
    {:ok, {_ip, port}} = ThousandIsland.listener_info(state.bandit)
    {:reply, port, state}
  end

  @impl true
  def handle_info(:listen, %{bandit: nil} = state), do: {:noreply, listen(state)}
  def handle_info(:listen, state), do: {:noreply, state}

  def handle_info({:EXIT, pid, reason}, %{bandit: pid} = state),
    do: {:noreply, retry(%{state | bandit: nil}, reason)}

  def handle_info(_message, state), do: {:noreply, state}

  defp listen(state) do
    case Bandit.start_link(state.opts) do
      {:ok, pid} -> %{state | bandit: pid, retry_ms: @retry_min_ms}
      {:error, {:shutdown, {:failed_to_start_child, :listener, reason}}} -> retry(state, reason)
      {:error, reason} -> retry(state, reason)
    end
  end

  defp retry(state, reason) do
    Logger.error(
      "Shelly listener on port #{state.opts[:port]}: #{inspect(reason)}; " <>
        "retrying in #{state.retry_ms} ms"
    )

    Process.send_after(self(), :listen, state.retry_ms)
    %{state | retry_ms: min(state.retry_ms * 2, @retry_max_ms)}
  end
end
