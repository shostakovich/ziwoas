defmodule Ziwoas.Weather.CurrentJob do
  @moduledoc "Rails' `WeatherCurrentJob` (`fetch_current_weather`): the current observation."
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Weather.Sync

  @impl true
  def perform(context),
    do: Sync.perform(context, fn location, _today -> Sync.sync_current(location) end)
end
