defmodule Ziwoas.Weather.Sync do
  @moduledoc false
  require Logger

  alias Ziwoas.{Clock, Location, Plugs, Weather}
  alias Ziwoas.Weather.{BrightskyClient, Record}

  @forecast_max_days 10

  @type error :: {:error, BrightskyClient.reason() | Ecto.Changeset.t()}

  @spec perform(keyword, (Location.t(), Date.t() -> :ok | {:ok, term} | error)) ::
          :ok | error
  def perform(opts, sync) do
    location = Keyword.fetch!(opts, :config).location
    today = Clock.today(location.timezone)

    case sync.(location, today) do
      {:error, reason} = error ->
        Logger.warning("Bright Sky sync failed: #{describe(reason)}")
        error

      _ok ->
        Weather.notify_synced(today)
    end
  end

  defp describe(%Ecto.Changeset{errors: errors}), do: "invalid record #{inspect(errors)}"
  defp describe(%{__exception__: true} = exception), do: Exception.message(exception)
  defp describe(reason), do: inspect(reason)

  @spec sync_current(Location.t()) :: {:ok, Record.t()} | error
  def sync_current(%Location{} = location) do
    with {:ok, row} <- BrightskyClient.current_weather(location) do
      Weather.replace_current(location, row)
    end
  end

  @spec sync_today(Location.t(), Date.t()) :: :ok | error
  def sync_today(%Location{} = location, %Date{} = today) do
    case BrightskyClient.weather_for_date(location, today) do
      {:ok, rows} -> Weather.put_forecast(location, rows)
      {:error, {:http_status, 404}} -> :ok
      error -> error
    end
  end

  @spec sync_forecast(Location.t(), Date.t(), pos_integer) :: :ok | error
  def sync_forecast(%Location{} = location, %Date{} = today, max_days \\ @forecast_max_days) do
    Enum.reduce_while(1..max_days, :ok, fn offset, :ok ->
      case BrightskyClient.weather_for_date(location, Date.add(today, offset)) do
        {:ok, []} -> {:halt, :ok}
        {:error, {:http_status, 404}} -> {:halt, :ok}
        {:ok, rows} -> {:cont, Weather.put_forecast(location, rows)}
        error -> {:halt, error}
      end
    end)
  end

  @spec sync_historic_date(Location.t(), Date.t()) :: :ok | error
  def sync_historic_date(%Location{} = location, %Date{} = date) do
    case BrightskyClient.weather_for_date(location, date) do
      {:ok, rows} -> Weather.put_historic(location, rows)
      {:error, {:http_status, 404}} -> :ok
      error -> error
    end
  end

  @spec backfill_historic_from_daily_totals(Location.t()) :: :ok | error
  def backfill_historic_from_daily_totals(%Location{} = location) do
    Plugs.dates_with_daily_totals()
    |> Enum.reject(&Weather.historic_complete?(location, &1))
    |> Enum.reduce_while(:ok, fn date, :ok ->
      case sync_historic_date(location, date) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
