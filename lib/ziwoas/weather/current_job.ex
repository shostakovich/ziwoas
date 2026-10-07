defmodule Ziwoas.Weather.CurrentJob do
  @moduledoc false
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Weather.Sync

  @impl true
  def perform(context),
    do: Sync.perform(context, fn location, _today -> Sync.sync_current(location) end)
end
