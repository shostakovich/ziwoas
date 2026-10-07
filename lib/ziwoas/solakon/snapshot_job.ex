defmodule Ziwoas.Solakon.SnapshotJob do
  @moduledoc """
  Rails' `Solakon::SnapshotJob` (`every 2 minutes`, task `solakon_monitor`): the
  full register snapshot — panels, battery, energy counters, status — read through
  `Ziwoas.Solakon.Monitor` into a `solakon_snapshots` row. Nothing is broadcast,
  as in Rails.
  """
  @behaviour Ziwoas.Scheduler.Job

  # Beyond the scheduler's context, tests pass `:config` and `:monitor`.

  require Logger

  alias Ziwoas.{Clock, Config, Repo}
  alias Ziwoas.Solakon.{Monitor, Snapshot}

  @impl true
  def perform(%{task: task} = context) do
    solakon = Map.get_lazy(context, :config, &Config.app_config/0).solakon

    cond do
      is_nil(solakon) ->
        Logger.info("solakon_snapshot: not configured")

      not solakon.monitoring_enabled ->
        Logger.info("solakon_snapshot: monitoring disabled")

      true ->
        case Monitor.read_snapshot(Map.get(context, :monitor, Monitor)) do
          {:ok, data} ->
            {:ok, Repo.write(task, fn -> Repo.insert!(Snapshot.from_data(data, Clock.now())) end)}

          {:error, reason} ->
            Logger.warning("solakon_snapshot: Modbus failure: #{inspect(reason)}")
        end
    end
  end
end
