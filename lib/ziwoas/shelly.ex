defmodule Ziwoas.Shelly do
  @moduledoc false
  alias Ziwoas.Config
  alias Ziwoas.Shelly.Listener

  @registry Ziwoas.Shelly.Registry
  @call_timeout_ms 5_000

  @type error :: :offline | :timeout | {:rpc, integer | nil, String.t()}
  def registry, do: @registry

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

  @spec connection(String.t()) :: pid | nil
  def connection(plug_id) do
    case Registry.lookup(@registry, plug_id) do
      [] -> nil
      connections -> connections |> Enum.max_by(&elem(&1, 1)) |> elem(0)
    end
  end

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
