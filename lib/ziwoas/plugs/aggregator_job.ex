defmodule Ziwoas.Plugs.AggregatorJob do
  @moduledoc """
  The nightly aggregation (`aggregate_energy_samples`, 3:15): folds the
  finished days into `samples_5min`, `daily_totals` and
  `daily_energy_summary`, purges old raw samples, backs the database up and
  condenses the inverter readings into PV hours.

  Opts: `:config`, and `:backup_dir` (`config :ziwoas, :backup_dir`); without
  one nothing is backed up, as in tests, where `VACUUM INTO` cannot run inside
  the transaction the sandbox wraps around a test.
  """
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.Clock
  alias Ziwoas.Plugs.Aggregator
  alias Ziwoas.Solakon.PvHourAggregator

  @impl true
  def perform(opts) do
    config = Keyword.fetch!(opts, :config)
    zone = config.location.timezone
    today = Clock.today(zone)

    Logger.info("aggregator: starting scheduled run")

    [timezone: zone, plugs: config.plugs]
    |> Aggregator.new()
    |> Aggregator.run_once(today: today)

    if dir = opts[:backup_dir], do: Aggregator.backup!(dir, today)
    PvHourAggregator.run_once(zone, today)

    Logger.info("aggregator: done")
  end
end
