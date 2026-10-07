defmodule Ziwoas.Weather do
  @moduledoc """
  The weather records the Wetter page shows. `timestamp` is the end of the period a record sums up: 10 minutes
  for `current`, 60 for `forecast` and `historic`.
  """
  import Ecto.Query

  alias Ziwoas.Repo
  alias Ziwoas.Weather.{Day, Icon, Record}

  @doc "The newest `current` record, or nil."
  @spec latest_current() :: Record.t() | nil
  def latest_current do
    Repo.one(
      from r in Record, where: r.kind == "current", order_by: [desc: r.updated_at], limit: 1
    )
  end

  @doc """
  Asset and alt text for the dashboard hero, with the sunny default that
  stands in until the first weather sync.
  """
  @spec dashboard_icon() :: {String.t(), String.t()}
  def dashboard_icon do
    case latest_current() do
      nil -> {"icon_sonne.webp", "Sonne"}
      record -> {asset_name(record), presence(record.icon) || "Sonne"}
    end
  end

  defp presence(nil), do: nil
  defp presence(text), do: if(String.trim(text) == "", do: nil, else: text)

  @doc "Forecast and historic hours from the start of this hour to the end of tomorrow."
  @spec today_hourly(DateTime.t(), String.t()) :: [Record.t()]
  def today_hourly(now, zone) do
    local = DateTime.shift_zone!(now, zone)
    from = %{local | minute: 0, second: 0, microsecond: {0, 6}}
    to = end_of_day(Date.add(DateTime.to_date(local), 1), zone)

    Repo.all(
      from r in Record,
        where:
          r.kind in ["forecast", "historic"] and
            r.timestamp >= ^from and r.timestamp <= ^to,
        order_by: r.timestamp
    )
  end

  @doc "The forecast after today, one `Day` per local date."
  @spec future_days(Date.t(), String.t()) :: [Day.t()]
  def future_days(today, zone) do
    from(r in Record,
      where: r.kind == "forecast" and r.timestamp > ^end_of_day(today, zone),
      order_by: r.timestamp
    )
    |> Repo.all()
    |> Enum.chunk_by(&DateTime.to_date(local_time(&1, zone)))
    |> Enum.map(fn [first | _] = records ->
      %Day{date: DateTime.to_date(local_time(first, zone)), records: records, zone: zone}
    end)
  end

  @spec local_time(Record.t(), String.t()) :: DateTime.t()
  def local_time(%Record{timestamp: timestamp}, zone), do: DateTime.shift_zone!(timestamp, zone)

  @spec asset_name(Record.t()) :: String.t()
  def asset_name(%Record{icon: icon, daytime: daytime}), do: Icon.asset_name(icon, daytime)

  @spec period_minutes(Record.t()) :: 10 | 60
  def period_minutes(%Record{kind: "current"}), do: 10
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
    naive |> Ziwoas.LocalDay.to_instant(zone) |> utc()
  end

  defp utc(instant), do: DateTime.shift_zone!(instant, "Etc/UTC")
end
