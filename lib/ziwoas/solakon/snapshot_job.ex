defmodule Ziwoas.Solakon.SnapshotJob do
  @moduledoc """
  Every two minutes: the full register snapshot — panels, battery, energy
  counters, status — read through `Ziwoas.Solakon.Monitor` into a
  `solakon_snapshots` row, then `Ziwoas.Solakon`'s subscribers hear of it.

  Opts: `:monitor`, the monitor process (`Ziwoas.Solakon.Monitor`).
  """
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.{Clock, Solakon}
  alias Ziwoas.Solakon.Monitor

  @impl true
  def perform(opts) do
    case Monitor.read_snapshot(Keyword.get(opts, :monitor, Monitor)) do
      {:ok, data} ->
        with {:ok, snapshot} = ok <- Solakon.insert_snapshot(data, Clock.now()) do
          Solakon.notify_snapshot(snapshot)
          ok
        end

      {:error, reason} = error ->
        Logger.warning("solakon_snapshot: Modbus failure: #{inspect(reason)}")
        error
    end
  end
end
