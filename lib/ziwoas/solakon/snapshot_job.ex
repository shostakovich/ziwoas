defmodule Ziwoas.Solakon.SnapshotJob do
  @moduledoc false
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
