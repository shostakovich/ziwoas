defmodule Ziwoas.Weather.Sync do
  @moduledoc """
  Bright Sky into `weather_records`: one `current` row per location, `forecast`
  hours that a day's observations later replace as `historic`. Rows are keyed by
  kind, location and timestamp (`idx_weather_records_identity`); syncing a known
  hour again updates its row.
  """
  import Ecto.Query

  require Logger

  alias Ziwoas.{Clock, Live, LocalDay, Location, Repo}
  alias Ziwoas.Plugs.DailyTotal
  alias Ziwoas.Weather.{BrightskyClient, Record}

  @forecast_max_days 10
  @identity [:kind, :lat, :lon, :timestamp]

  @doc """
  A weather job's frame: runs `sync` with the configured location and today's
  date, then tells the Wetter page. Without coordinates it logs and does nothing.
  """
  @spec perform(Ziwoas.Scheduler.Job.context(), (Location.t(), Date.t() -> any)) :: :ok
  def perform(context, sync) do
    location = Ziwoas.Scheduler.Job.config(context).location

    if Location.located?(location) do
      sync.(location, Clock.today(location.timezone))
      Live.broadcast("weather", {:weather_updated})
    else
      Logger.info("weather: not configured")
    end

    :ok
  end

  @spec sync_current(Location.t()) :: Record.t()
  def sync_current(%Location{} = location) do
    row = BrightskyClient.current_weather(location)
    {lat, lon} = coordinates(location)

    {:ok, record} =
      Repo.transact(fn ->
        Repo.delete_all(
          from r in Record, where: r.kind == "current" and r.lat == ^lat and r.lon == ^lon
        )

        {:ok, Repo.insert!(changeset("current", row, location))}
      end)

    record
  end

  @spec sync_today(Location.t(), Date.t()) :: :ok
  def sync_today(%Location{} = location, %Date{} = today) do
    case BrightskyClient.weather_for_date(location, today) do
      :range_end -> :ok
      rows -> Enum.each(rows, &upsert!("forecast", &1, location))
    end
  end

  @doc "The days after `today`, one request each, until Bright Sky has no more."
  @spec sync_forecast(Location.t(), Date.t(), pos_integer) :: :ok
  def sync_forecast(%Location{} = location, %Date{} = today, max_days \\ @forecast_max_days) do
    Enum.reduce_while(1..max_days, :ok, fn offset, :ok ->
      case BrightskyClient.weather_for_date(location, Date.add(today, offset)) do
        rows when rows in [:range_end, []] ->
          {:halt, :ok}

        rows ->
          Enum.each(rows, &upsert!("forecast", &1, location))
          {:cont, :ok}
      end
    end)
  end

  @doc "A day's observed hours as `historic`, each replacing the forecast for its hour."
  @spec sync_historic_date(Location.t(), Date.t()) :: :ok
  def sync_historic_date(%Location{} = location, %Date{} = date) do
    case BrightskyClient.weather_for_date(location, date) do
      :range_end ->
        :ok

      rows ->
        {lat, lon} = coordinates(location)

        Enum.each(rows, fn row ->
          Repo.delete_all(
            from r in Record,
              where:
                r.kind == "forecast" and r.lat == ^lat and r.lon == ^lon and
                  r.timestamp == ^row.timestamp
          )

          upsert!("historic", row, location)
        end)
    end
  end

  @doc "Fetches the observations of every day with energy totals that lacks 24 historic hours."
  @spec backfill_historic_from_daily_totals(Location.t()) :: :ok
  def backfill_historic_from_daily_totals(%Location{} = location) do
    from(d in DailyTotal, distinct: true, select: d.date)
    |> Repo.all()
    |> Enum.sort()
    |> Enum.map(&Date.from_iso8601!/1)
    |> Enum.reject(&historic_complete?(location, &1))
    |> Enum.each(&sync_historic_date(location, &1))
  end

  defp upsert!(kind, row, location) do
    Repo.insert!(changeset(kind, row, location),
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: @identity
    )
  end

  defp changeset(kind, row, location) do
    {lat, lon} = coordinates(location)
    Record.changeset(Map.merge(row, %{kind: kind, lat: lat, lon: lon}))
  end

  defp coordinates(%Location{lat: lat, lon: lon}), do: {lat * 1.0, lon * 1.0}

  # The hours from local midnight to the next one.
  defp historic_complete?(location, date) do
    {lat, lon} = coordinates(location)
    from = date |> LocalDay.midnight(location.timezone) |> utc()
    to = date |> Date.add(1) |> LocalDay.midnight(location.timezone) |> utc()

    Repo.aggregate(
      from(r in Record,
        where:
          r.kind == "historic" and r.lat == ^lat and r.lon == ^lon and
            r.timestamp >= ^from and r.timestamp < ^to
      ),
      :count
    ) >= 24
  end

  defp utc(time), do: DateTime.shift_zone!(time, "Etc/UTC")
end
