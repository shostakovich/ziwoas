defmodule Ziwoas.Weather.HistoricJob do
  @moduledoc """
  The `fetch_historic_weather` job: yesterday's observations, then every day
  with energy totals that still lacks them — the backfill runs even when
  yesterday failed. The job fails with the first error; when both fail,
  yesterday's is logged here and the backfill's is returned.
  """
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.Weather.Sync

  @impl true
  def perform(context) do
    Sync.perform(context, fn location, today ->
      yesterday = Sync.sync_historic_date(location, Date.add(today, -1))

      case {yesterday, Sync.backfill_historic_from_daily_totals(location)} do
        {yesterday, :ok} ->
          yesterday

        {:ok, backfill} ->
          backfill

        {{:error, reason}, backfill} ->
          Logger.warning("Bright Sky historic sync of yesterday failed: #{inspect(reason)}")
          backfill
      end
    end)
  end
end
