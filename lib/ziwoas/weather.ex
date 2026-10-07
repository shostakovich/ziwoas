defmodule Ziwoas.Weather do
  @moduledoc """
  The weather records (`weather_records`). `timestamp` is the end of the period
  a record sums up: 10 minutes for `current`, 60 for `forecast` and `historic`.
  Rows are keyed by kind, location and timestamp (`idx_weather_records_identity`);
  storing a known hour again updates its row.

  `subscribe/0` delivers `{:synced, local_date}` after a sync with Bright Sky.
  """
  import Ecto.Query

  alias Ziwoas.{LocalDay, Location, Repo}
  alias Ziwoas.Weather.{Day, Record}

  @topic inspect(__MODULE__)
  @identity [:kind, :lat, :lon, :timestamp]
  @icons ~w[clear partly-cloudy cloudy fog wind rain sleet snow hail thunderstorm unknown]

  @spec subscribe() :: :ok | {:error, term}
  def subscribe, do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)

  @doc "Tells the subscribers that a sync on the local date `today` is stored."
  @spec notify_synced(Date.t()) :: :ok
  def notify_synced(%Date{} = today), do: broadcast(:synced, today)

  defp broadcast(event, payload),
    do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, @topic, {event, payload})

  # --- Storing --------------------------------------------------------------------

  @doc "Replaces the `current` record at `location` with one from Bright Sky's `attrs`."
  @spec replace_current(Location.t(), map) :: {:ok, Record.t()} | {:error, Ecto.Changeset.t()}
  def replace_current(%Location{} = location, attrs) do
    {lat, lon} = coordinates(location)

    Repo.transact(fn ->
      Repo.delete_all(
        from r in Record, where: r.kind == :current and r.lat == ^lat and r.lon == ^lon
      )

      Repo.insert(changeset(:current, attrs, location))
    end)
  end

  @doc "Stores Bright Sky's hours at `location` as `forecast`."
  @spec put_forecast(Location.t(), [map]) :: :ok | {:error, Ecto.Changeset.t()}
  def put_forecast(%Location{} = location, rows),
    do: transact_each(rows, &upsert(:forecast, &1, location))

  @doc "Stores observed hours at `location` as `historic`, each replacing the forecast for its hour."
  @spec put_historic(Location.t(), [map]) :: :ok | {:error, Ecto.Changeset.t()}
  def put_historic(%Location{} = location, rows) do
    {lat, lon} = coordinates(location)

    transact_each(rows, fn row ->
      Repo.delete_all(
        from r in Record,
          where:
            r.kind == :forecast and r.lat == ^lat and r.lon == ^lon and
              r.timestamp == ^row.timestamp
      )

      upsert(:historic, row, location)
    end)
  end

  @doc "Whether `location` has the 24 `historic` hours from local midnight of `date` to the next."
  @spec historic_complete?(Location.t(), Date.t()) :: boolean
  def historic_complete?(%Location{} = location, %Date{} = date) do
    {lat, lon} = coordinates(location)
    from = date |> LocalDay.midnight(location.timezone) |> utc()
    to = date |> Date.add(1) |> LocalDay.midnight(location.timezone) |> utc()

    Repo.aggregate(
      from(r in Record,
        where:
          r.kind == :historic and r.lat == ^lat and r.lon == ^lon and
            r.timestamp >= ^from and r.timestamp < ^to
      ),
      :count
    ) >= 24
  end

  # Stores every row in one transaction, or none.
  defp transact_each(rows, store) do
    with {:ok, _stored} <-
           Repo.transact(fn -> Enum.reduce_while(rows, {:ok, 0}, &store_next(store, &1, &2)) end),
         do: :ok
  end

  defp store_next(store, row, {:ok, stored}) do
    case store.(row) do
      {:ok, _record} -> {:cont, {:ok, stored + 1}}
      {:error, _changeset} = error -> {:halt, error}
    end
  end

  defp upsert(kind, row, location) do
    Repo.insert(changeset(kind, row, location),
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: @identity
    )
  end

  defp changeset(kind, row, location) do
    {lat, lon} = coordinates(location)
    Record.changeset(Map.merge(row, %{kind: kind, lat: lat, lon: lon}))
  end

  defp coordinates(%Location{lat: lat, lon: lon}), do: {lat * 1.0, lon * 1.0}

  # --- Reading --------------------------------------------------------------------

  @doc """
  The `historic` records at `location` with timestamps in `[from, to)`, oldest
  first; none without coordinates.
  """
  @spec historic_records(Location.t(), DateTime.t(), DateTime.t()) :: [Record.t()]
  def historic_records(%Location{} = location, %DateTime{} = from, %DateTime{} = to) do
    if Location.located?(location) do
      Repo.all(
        from r in Record,
          where:
            r.kind == :historic and r.lat == ^location.lat and r.lon == ^location.lon and
              r.timestamp >= ^from and r.timestamp < ^to,
          order_by: r.timestamp
      )
    else
      []
    end
  end

  @doc "The newest `current` record, or nil."
  @spec latest_current() :: Record.t() | nil
  def latest_current do
    Repo.one(
      from r in Record, where: r.kind == :current, order_by: [desc: r.updated_at], limit: 1
    )
  end

  @doc "Forecast and historic hours from the start of this hour to the end of tomorrow."
  @spec today_hourly(DateTime.t(), String.t()) :: [Record.t()]
  def today_hourly(now, zone) do
    local = DateTime.shift_zone!(now, zone)
    from = %{local | minute: 0, second: 0, microsecond: {0, 6}}
    to = end_of_day(Date.add(DateTime.to_date(local), 1), zone)

    Repo.all(
      from r in Record,
        where:
          r.kind in [:forecast, :historic] and
            r.timestamp >= ^from and r.timestamp <= ^to,
        order_by: r.timestamp
    )
  end

  @doc "The forecast after today, one `Day` per local date."
  @spec future_days(Date.t(), String.t()) :: [Day.t()]
  def future_days(today, zone) do
    from(r in Record,
      where: r.kind == :forecast and r.timestamp > ^end_of_day(today, zone),
      order_by: r.timestamp
    )
    |> Repo.all()
    |> Enum.chunk_by(&DateTime.to_date(local_time(&1, zone)))
    |> Enum.map(fn [first | _] = records ->
      %Day{date: DateTime.to_date(local_time(first, zone)), records: records, zone: zone}
    end)
  end

  # --- Values ---------------------------------------------------------------------

  @spec local_time(Record.t(), String.t()) :: DateTime.t()
  def local_time(%Record{timestamp: timestamp}, zone), do: DateTime.shift_zone!(timestamp, zone)

  @doc "Bright Sky's icon without its -day/-night suffix; anything unknown is \"unknown\"."
  @spec base_icon(String.t() | nil) :: String.t()
  def base_icon(icon) do
    raw =
      (icon || "")
      |> String.replace_suffix("-day", "")
      |> String.replace_suffix("-night", "")

    if raw in @icons, do: raw, else: "unknown"
  end

  @doc ~s("day" or "night": the icon's suffix when it has one, else where the sun stands.)
  @spec daytime_for(String.t() | nil, DateTime.t(), Location.t()) :: String.t()
  def daytime_for(icon, timestamp, location) do
    icon = icon || ""

    cond do
      String.ends_with?(icon, "-day") -> "day"
      String.ends_with?(icon, "-night") -> "night"
      Ziwoas.Sun.daytime?(location, timestamp) -> "day"
      true -> "night"
    end
  end

  @spec period_minutes(Record.t()) :: 10 | 60
  def period_minutes(%Record{kind: :current}), do: 10
  def period_minutes(%Record{}), do: 60

  @doc "`solar` (kWh/m² over the period) as average W/m²."
  @spec solar_w_per_m2(Record.t()) :: float | nil
  def solar_w_per_m2(%Record{solar: nil}), do: nil

  def solar_w_per_m2(%Record{solar: solar} = record),
    do: solar * 1000.0 * (60.0 / period_minutes(record))

  @doc "Sum of `precipitation`, missing values as 0."
  @spec precip_sum([Record.t()]) :: number
  def precip_sum(records), do: records |> Enum.map(&(&1.precipitation || 0)) |> Enum.sum()

  @spec min_of([Record.t()], atom) :: number | nil
  def min_of(records, field), do: records |> present(field) |> extreme(&Enum.min/1)

  @spec max_of([Record.t()], atom) :: number | nil
  def max_of(records, field), do: records |> present(field) |> extreme(&Enum.max/1)

  defp present(records, field),
    do: records |> Enum.map(&Map.fetch!(&1, field)) |> Enum.reject(&is_nil/1)

  defp extreme([], _fun), do: nil
  defp extreme(values, fun), do: fun.(values)

  # The last microsecond of the local day.
  defp end_of_day(date, zone) do
    {:ok, naive} = NaiveDateTime.new(date, ~T[23:59:59.999999])
    naive |> LocalDay.to_instant(zone) |> utc()
  end

  defp utc(instant), do: DateTime.shift_zone!(instant, "Etc/UTC")
end
