defmodule Ziwoas.Plugs.AggregatorJob do
  @moduledoc """
  The nightly aggregation (`aggregate_energy_samples`, 3:15): folds the
  finished days into `samples_5min`, `daily_totals` and the daily energy
  summaries, purges old raw samples, backs the database up and condenses the
  inverter readings into PV hours.

  Opts: `:config`, and `:backup_dir` (`config :ziwoas, :backup_dir`); without
  one nothing is backed up, as in tests, where `VACUUM INTO` cannot run inside
  the transaction the sandbox wraps around a test.
  """
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.{Clock, Plugs}
  alias Ziwoas.Solakon.PvHourAggregator

  @impl true
  def perform(opts) do
    config = Keyword.fetch!(opts, :config)
    zone = config.location.timezone
    today = Clock.today(zone)

    Logger.info("aggregator: starting scheduled run")

    Plugs.aggregate(zone, config.plugs, today: today)
    if dir = opts[:backup_dir], do: Plugs.backup!(dir, today)
    PvHourAggregator.run_once(zone, today)

    Logger.info("aggregator: done")
  end
end
