defmodule Ziwoas.Weather.HistoricJob do
  @moduledoc false
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
