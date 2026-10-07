defmodule Ziwoas.Weather.CurrentJob do
  @moduledoc "The `fetch_current_weather` job: the current observation."
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Weather.Sync

  @impl true
  def perform(context),
    do: Sync.perform(context, fn location, _today -> Sync.sync_current(location) end)
end
