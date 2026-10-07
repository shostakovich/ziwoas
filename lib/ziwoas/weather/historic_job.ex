defmodule Ziwoas.Weather.HistoricJob do
  @moduledoc """
  The `fetch_historic_weather` job: yesterday's observations, then every day
  with energy totals that still lacks them.
  """
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Weather.Sync

  @impl true
  def perform(context) do
    Sync.perform(context, fn location, today ->
      Sync.sync_historic_date(location, Date.add(today, -1))
      Sync.backfill_historic_from_daily_totals(location)
    end)
  end
end
