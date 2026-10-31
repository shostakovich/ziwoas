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

    step(:plugs, fn -> Plugs.aggregate(zone, config.plugs, today: today) end)
    if dir = opts[:backup_dir], do: step(:backup, fn -> Plugs.backup!(dir, today) end)
    step(:pv_hours, fn -> PvHourAggregator.run_once(zone, today) end)

    Logger.info("aggregator: done")
  end

  defp step(name, fun) do
    fun.()
  rescue
    error ->
      Logger.error(
        "aggregator: #{name} failed: " <> Exception.format(:error, error, __STACKTRACE__)
      )
  end
end
