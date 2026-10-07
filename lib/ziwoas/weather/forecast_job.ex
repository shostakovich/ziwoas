defmodule Ziwoas.Weather.ForecastJob do
  @moduledoc "Rails' `WeatherForecastJob` (`fetch_weather_forecast`): the days after today."
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Weather.Sync

  @impl true
  def perform(context), do: Sync.perform(context, &Sync.sync_forecast(&1, &2))
end
