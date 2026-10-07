defmodule Ziwoas.Shelly do
  @moduledoc """
  Shelly plugs over their outbound websocket (ADR-0008): each plug connects to
  `ws://<host>:<shelly_port>/shelly/<plug id>` (`Ziwoas.Shelly.Listener`), one
  `Ziwoas.Shelly.Connection` per plug records its status and carries its RPC calls.

  Connections register in `Ziwoas.Shelly.Registry` under the plug id; the newest one
  is the plug's.
  """
  alias Ziwoas.Config
  alias Ziwoas.Shelly.Listener

  @registry Ziwoas.Shelly.Registry
  @call_timeout_ms 5_000

  @type error :: :offline | :timeout | {:rpc, integer | nil, String.t()}

  @doc "The registry the connections register in."
  def registry, do: @registry

  @doc """
  Calls `method` on the plug's Shelly and waits for its answer: `{:error, :offline}`
  without a connection, `{:error, :timeout}` without an answer in `timeout` ms.
  """
  @spec call(String.t(), String.t(), map, timeout) :: {:ok, term} | {:error, error}
  def call(plug_id, method, params, timeout \\ @call_timeout_ms) do
    case connection(plug_id) do
      nil -> {:error, :offline}
      pid -> await(pid, method, params, timeout)
    end
  end

  # The monitor's alias is the reply address; once it is gone a late reply is dropped.
  defp await(pid, method, params, timeout) do
    ref = Process.monitor(pid, alias: :reply_demonitor)
    send(pid, {:rpc, ref, method, params})

    receive do
      {^ref, reply} -> reply
      {:DOWN, ^ref, :process, _pid, _reason} -> {:error, :offline}
    after
      timeout ->
        Process.demonitor(ref, [:flush])

        receive do
          {^ref, reply} -> reply
        after
          0 -> {:error, :timeout}
        end
    end
  end

  @doc "The plug's newest connection, if any."
  @spec connection(String.t()) :: pid | nil
  def connection(plug_id) do
    case Registry.lookup(@registry, plug_id) do
      [] -> nil
      connections -> connections |> Enum.max_by(&elem(&1, 1)) |> elem(0)
    end
  end

  @doc "The listener the plugs of `config` connect to, on `port`."
  @spec listener_spec(Config.t(), :inet.port_number()) :: Supervisor.child_spec()
  def listener_spec(%Config{} = config, port),
    do:
      Supervisor.child_spec(
        {Bandit,
         plug: {Listener, roster: Config.plug_roster(config)},
         port: port,
         startup_log: false,
         thousand_island_options: [num_acceptors: 2]},
        id: Listener
      )
end
