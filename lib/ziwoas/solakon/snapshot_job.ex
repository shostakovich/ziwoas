defmodule Ziwoas.Solakon.SnapshotJob do
  @moduledoc """
  Every two minutes: the full register snapshot — panels, battery, energy
  counters, status — read through `Ziwoas.Solakon.Monitor` into a
  `solakon_snapshots` row. Nothing is broadcast.
  """
  @behaviour Ziwoas.Scheduler.Job

  # Beyond the scheduler's context, tests pass `:config` and `:monitor`.

  require Logger

  alias Ziwoas.{Clock, Repo}
  alias Ziwoas.Scheduler.Job
  alias Ziwoas.Solakon.{Monitor, Snapshot}

  @impl true
  def perform(context) do
    solakon = Job.config(context).solakon

    cond do
      is_nil(solakon) ->
        Logger.debug("solakon_snapshot: not configured")

      not solakon.monitoring_enabled ->
        Logger.info("solakon_snapshot: monitoring disabled")

      true ->
        case Monitor.read_snapshot(Map.get(context, :monitor, Monitor)) do
          {:ok, data} ->
            Repo.insert(Snapshot.from_data(data, Clock.now()))

          {:error, reason} = error ->
            Logger.warning("solakon_snapshot: Modbus failure: #{inspect(reason)}")
            error
        end
    end
  end
end
