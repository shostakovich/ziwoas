defmodule Ziwoas.Weather.Sync do
  @moduledoc """
  Bright Sky into `weather_records` (Rails' `WeatherSync`): one `current` row per
  location, `forecast` hours that a day's observations later replace as
  `historic`. Rows are keyed by kind, location and timestamp; values are cast as
  Rails casts them (`Ziwoas.RailsCast`), so both apps store the same bytes
  (`test/vectors/weather_sync.json`).

  Writes through the process's repo: the jobs wrap it in `Ziwoas.Repo.write/2`.
  """
  import Ecto.Query

  require Logger

  alias Ziwoas.{Clock, Live, LocalDay, Location, RailsCast, Repo}
  alias Ziwoas.Ecto.RailsDateTime
  alias Ziwoas.Plugs.DailyTotal
  alias Ziwoas.Weather.{BrightskyClient, Record}

  @forecast_max_days 10

  @floats ~w[precipitation pressure_msl sunshine temperature wind_speed dew_point wind_gust_speed solar]a
  @integers ~w[source_id wind_direction cloud_cover relative_humidity visibility wind_gust_direction
               precipitation_probability precipitation_probability_6h]a
  @strings ~w[condition icon daytime]a

  @doc """
  A weather job's frame (Rails' `WeatherSync.from_app_config` and the
  broadcast after it): runs `sync` with the configured location and today's
  date inside `Repo.write(task, …)`, then tells the Wetter page — as owner only.
  Without coordinates it logs and does nothing.
  """
  @spec perform(Ziwoas.Scheduler.Job.context(), (Location.t(), Date.t() -> any)) :: :ok
  def perform(%{task: task} = context, sync) do
    location = Ziwoas.Scheduler.Job.config(context).location

    if Location.located?(location) do
      today = Clock.today(location.timezone)
      Repo.write(task, fn -> sync.(location, today) end)
      Live.broadcast(task, "weather", {:weather_updated})
    else
      Logger.info("weather: not configured")
    end

    :ok
  end

  @spec sync_current(Location.t()) :: Record.t()
  def sync_current(%Location{} = location) do
    row = BrightskyClient.current_weather(location)
    {lat, lon} = coordinates(location)

    Repo.delete_all(
      from r in Record, where: r.kind == "current" and r.lat == ^lat and r.lon == ^lon
    )

    Repo.insert!(struct(Record, attrs("current", row, location)))
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
    {lat, lon} = coordinates(location)
    attrs = attrs(kind, row, location)

    existing =
      Repo.one(
        from r in Record,
          where:
            r.kind == ^kind and r.lat == ^lat and r.lon == ^lon and
              r.timestamp == ^attrs.timestamp
      )

    case existing do
      nil -> Repo.insert!(struct(Record, attrs))
      record -> record |> Ecto.Changeset.change(Map.delete(attrs, :timestamp)) |> Repo.update!()
    end
  end

  defp attrs(kind, row, location) do
    {lat, lon} = coordinates(location)

    row
    |> Map.new(fn
      {key, value} when key in @floats -> {key, RailsCast.float(value)}
      {key, value} when key in @integers -> {key, RailsCast.integer(value)}
      {key, value} when key in @strings -> {key, RailsCast.string(value)}
      {:timestamp, value} -> {:timestamp, value}
    end)
    |> Map.merge(%{kind: kind, lat: lat, lon: lon})
  end

  defp coordinates(location), do: {RailsCast.float(location.lat), RailsCast.float(location.lon)}

  # Rails' `date.beginning_of_day..date.end_of_day` in the configured zone.
  defp historic_complete?(location, date) do
    {lat, lon} = coordinates(location)
    zone = location.timezone
    from = LocalDay.midnight(date, zone) |> utc()
    to = date |> NaiveDateTime.new!(~T[23:59:59.999999]) |> LocalDay.to_instant(zone) |> utc()

    Repo.aggregate(
      from(r in Record,
        where:
          r.kind == "historic" and r.lat == ^lat and r.lon == ^lon and
            r.timestamp >= type(^from, RailsDateTime) and r.timestamp <= type(^to, RailsDateTime)
      ),
      :count
    ) >= 24
  end

  defp utc(time), do: DateTime.shift_zone!(time, "Etc/UTC")
end
