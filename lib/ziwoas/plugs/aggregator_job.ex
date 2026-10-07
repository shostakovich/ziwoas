defmodule Ziwoas.Plugs.AggregatorJob do
  @moduledoc """
  The nightly aggregation (`aggregate_energy_samples`, 3:15): folds the
  finished days into `samples_5min`, `daily_totals` and
  `daily_energy_summary`, purges old raw samples, backs the database up and
  condenses the inverter readings into PV hours.

  The backup directory is `config :ziwoas, :backup_dir`. A test passes
  `:backup_dir` in the context, as it passes `:config`
  (`Ziwoas.Scheduler.Job.config/1`), or `:backup`, a function of the directory
  and the day in place of `Aggregator.backup!/2`: `VACUUM INTO` cannot run
  inside the transaction a test's sandbox wraps around it.
  """
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.Clock
  alias Ziwoas.Plugs.Aggregator
  alias Ziwoas.Solakon.PvHourAggregator

  @impl true
  def perform(context) do
    config = Ziwoas.Scheduler.Job.config(context)
    zone = config.location.timezone
    today = Clock.today(zone)

    Logger.info("aggregator: starting scheduled run")

    [timezone: zone, plugs: config.plugs]
    |> Aggregator.new()
    |> Aggregator.run_once(today: today)

    backup(context, today)
    PvHourAggregator.run_once(zone, today)

    Logger.info("aggregator: done")
  end

  defp backup(context, today) do
    dir =
      Map.get_lazy(context, :backup_dir, fn -> Application.fetch_env!(:ziwoas, :backup_dir) end)

    backup = Map.get(context, :backup, &Aggregator.backup!/2)
    backup.(dir, today)
  end
end
