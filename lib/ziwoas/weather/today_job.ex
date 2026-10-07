defmodule Ziwoas.Weather.TodayJob do
  @moduledoc "The `fetch_today_weather` job: today's hours as forecast."
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Weather.Sync

  @impl true
  def perform(context), do: Sync.perform(context, &Sync.sync_today/2)
end
