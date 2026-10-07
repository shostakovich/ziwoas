defmodule Ziwoas.Plugs.AggregatorJob do
  @moduledoc false
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
