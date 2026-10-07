defmodule Ziwoas.Weather.TodayJob do
  @moduledoc false
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Weather.Sync

  @impl true
  def perform(context), do: Sync.perform(context, &Sync.sync_today/2)
end
