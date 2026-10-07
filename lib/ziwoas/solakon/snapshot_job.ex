defmodule Ziwoas.Solakon.SnapshotJob do
  @moduledoc """
  Every two minutes: the full register snapshot — panels, battery, energy
  counters, status — read through `Ziwoas.Solakon.Monitor` into a
  `solakon_snapshots` row. Nothing is broadcast.

  Opts: `:monitor`, the monitor process (`Ziwoas.Solakon.Monitor`).
  """
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.{Clock, Repo}
  alias Ziwoas.Solakon.{Monitor, Snapshot}

  @impl true
  def perform(opts) do
    case Monitor.read_snapshot(Keyword.get(opts, :monitor, Monitor)) do
      {:ok, data} ->
        Repo.insert(Snapshot.from_data(data, Clock.now()))

      {:error, reason} = error ->
        Logger.warning("solakon_snapshot: Modbus failure: #{inspect(reason)}")
        error
    end
  end
end
