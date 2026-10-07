defmodule Ziwoas.Energy.Report do
  @moduledoc """
  The energy report over a range of aggregated days: totals and ratios, a
  ranking per role, each consumer's daily energy, the power detail and the
  weather behind them. Days are summed in Wh and rounded only where a number
  is shown.

  The detail is 5-minute power for up to seven days (`:five_minutes`, with
  Unix `timestamps`), else the average power of each day (`:daily_mean`,
  with `dates`); each series carries signed watts, nil where a plug has none.
  """
  alias Ziwoas.{Economics, Plugs}
  alias Ziwoas.Energy
  alias Ziwoas.Energy.{Amount, DailyPoint, PowerSeries, ReportWeather}
  alias Ziwoas.LocalDay
  alias Ziwoas.Plugs.Roster

  defstruct [
    :start_date,
    :end_date,
    :first_date,
    :last_date,
    :summary,
    :daily_points,
    :producer_ranking,
    :consumer_ranking,
    :consumer_daily,
    :detail,
    :weather
  ]

  @type t :: %__MODULE__{}

  @typedoc "The last `n` aggregated days, or the days of a range (cut to the aggregated ones)."
  @type range :: {:last_days, pos_integer} | Date.Range.t()

  @max_five_minute_days 7

  @doc """
  Options: `:plugs`, `:location` (weather needs its coordinates), `:today`
  (the date an empty report shows) and `:prices` (default: the prices on
  record).
  """
  @spec build(range, keyword) :: t
  def build(range, opts) do
    roster = Roster.new(Keyword.fetch!(opts, :plugs))
    location = Keyword.fetch!(opts, :location)
    today = Keyword.fetch!(opts, :today)
    prices = Keyword.get_lazy(opts, :prices, &Economics.kwh_prices/0)

    case Plugs.daily_total_range() do
      nil -> empty(today, prices)
      aggregated -> report(range, aggregated, roster, location, prices)
    end
  end

  @spec empty?(t) :: boolean
  def empty?(%__MODULE__{daily_points: points}), do: points == []

  defp report(range, aggregated, roster, location, prices) do
    {first, last} = resolve(range, aggregated)
    rows = Plugs.daily_totals(first, last)
    daily_points = daily_points(Energy.daily_summaries(first, last), first, last)
    detail = detail(roster, location.timezone, rows, first, last)

    %__MODULE__{
      start_date: first,
      end_date: last,
      first_date: aggregated.first,
      last_date: aggregated.last,
      summary: summarize(daily_points, prices),
      daily_points: daily_points,
      producer_ranking: ranking(rows, roster, :producer),
      consumer_ranking: ranking(rows, roster, :consumer),
      consumer_daily: consumer_daily(roster, rows),
      detail: detail,
      weather: %{
        daily: ReportWeather.daily(location, first, last),
        hourly:
          if(detail.resolution == :five_minutes and detail.timestamps != [],
            do: ReportWeather.hourly(location, first, last),
            else: []
          )
      }
    }
  end

  # A typo like 1026 would span ~365,000 days: nothing before the first aggregated day,
  # unless that is less than a year back.
  defp resolve({:last_days, days}, aggregated),
    do: {Date.add(aggregated.last, -(days - 1)), aggregated.last} |> clamp(aggregated)

  defp resolve(%Date.Range{first: first, last: last}, aggregated) do
    last = Enum.min([last, aggregated.last], Date)
    clamp({Enum.min([first, last], Date), last}, aggregated)
  end

  defp clamp({first, last}, aggregated) do
    floor = Enum.min([aggregated.first, Date.add(last, -365)], Date)
    {Enum.max([first, floor], Date), last}
  end

  defp empty(today, prices) do
    %__MODULE__{
      start_date: today,
      end_date: today,
      first_date: today,
      last_date: today,
      summary: summarize([], prices),
      daily_points: [],
      producer_ranking: [],
      consumer_ranking: [],
      consumer_daily: [],
      detail: %{resolution: :five_minutes, timestamps: [], series: []},
      weather: %{daily: %{}, hourly: []}
    }
  end

  defp daily_points(summaries, first, last) do
    by_date = Map.new(summaries, &{&1.date, &1})

    for date <- Date.range(first, last) do
      case by_date do
        %{^date => summary} ->
          %DailyPoint{
            date: date,
            produced: Amount.wh(summary.produced_wh),
            consumed: Amount.wh(summary.consumed_wh),
            self_consumed: Amount.wh(summary.self_consumed_wh),
            covered: true
          }

        _ ->
          DailyPoint.uncovered(date)
      end
    end
  end

  defp summarize(daily_points, prices) do
    covered = Enum.filter(daily_points, & &1.covered)
    produced = covered |> Enum.map(& &1.produced) |> Amount.sum()
    consumed = covered |> Enum.map(& &1.consumed) |> Amount.sum()
    self_consumed = covered |> Enum.map(& &1.self_consumed) |> Amount.sum()
    days = length(covered)

    %{
      produced_kwh: rounded_kwh(produced),
      consumed_kwh: rounded_kwh(consumed),
      self_consumed_kwh: rounded_kwh(self_consumed),
      savings_eur: savings_eur(covered, prices),
      balance_kwh: rounded_kwh(Amount.subtract(produced, consumed)),
      avg_produced_kwh: average_kwh(produced, days),
      avg_consumed_kwh: average_kwh(consumed, days),
      autarky_ratio: Float.round(Amount.ratio_to(self_consumed, consumed), 4),
      self_consumption_ratio: Float.round(Amount.ratio_to(self_consumed, produced), 4)
    }
  end

  # Each day carries the price in force on it, so a range spanning a price change isn't levelled.
  defp savings_eur(covered_points, prices) do
    dated = Enum.map(covered_points, &{&1.date, &1.self_consumed})

    case Economics.total_savings_eur(prices, dated) do
      nil -> nil
      total -> Float.round(total * 1.0, 2)
    end
  end

  defp average_kwh(_total, 0), do: 0.0
  defp average_kwh(total, days), do: total |> Amount.divide(days) |> rounded_kwh()

  # position follows config order, the order the dashboard and charts colour plugs by.
  # Ties in kWh keep config order.
  defp ranking(rows, roster, role) do
    peers =
      if role == :producer, do: Roster.producer_ids(roster), else: Roster.consumer_ids(roster)

    rows = Enum.filter(rows, &(Roster.role_of(roster, &1.plug_id) == role))
    rows_by_plug = Enum.group_by(rows, & &1.plug_id)

    rows
    |> Enum.map(& &1.plug_id)
    |> Enum.uniq()
    |> Enum.sort_by(fn plug_id -> Enum.find_index(peers, &(&1 == plug_id)) end)
    |> Enum.map(fn plug_id ->
      %{
        plug_id: plug_id,
        name: Roster.find(roster, plug_id).name,
        role: role,
        position: Enum.find_index(peers, &(&1 == plug_id)),
        kwh:
          rows_by_plug[plug_id]
          |> Enum.map(& &1.energy_wh)
          |> Enum.sum()
          |> Amount.wh()
          |> rounded_kwh()
      }
    end)
    |> Enum.sort_by(& &1.kwh, :desc)
  end

  # Every consumer in config order, with the days it has a total for.
  defp consumer_daily(roster, rows) do
    by_plug = Enum.group_by(rows, & &1.plug_id)

    for plug <- Roster.consumers(roster) do
      wh_by_date = by_plug |> Map.get(plug.id, []) |> Map.new(&{&1.date, &1.energy_wh})
      %{plug_id: plug.id, name: plug.name, wh_by_date: wh_by_date}
    end
  end

  defp detail(roster, timezone, rows, first, last) do
    if Date.diff(last, first) >= @max_five_minute_days,
      do: daily_mean_detail(roster, rows, first, last),
      else: five_minute_detail(roster, timezone, first, last)
  end

  defp five_minute_detail(roster, timezone, first, last) do
    rows =
      Plugs.samples_5min(
        LocalDay.midnight_unix(first, timezone),
        LocalDay.midnight_unix(Date.add(last, 1), timezone)
      )

    timestamps = rows |> Enum.map(& &1.bucket_ts) |> Enum.uniq() |> Enum.sort()
    series = PowerSeries.from_5min(rows, roster)

    %{
      resolution: :five_minutes,
      timestamps: timestamps,
      series:
        present_series(roster, fn plug ->
          watts_by_ts = PowerSeries.signed_watts_by_ts(series, plug.id)
          Enum.map(timestamps, &watts_by_ts[&1])
        end)
    }
  end

  defp daily_mean_detail(roster, rows, first, last) do
    row_by_plug_and_date = Map.new(rows, &{{&1.plug_id, &1.date}, &1})
    dates = Enum.to_list(Date.range(first, last))

    %{
      resolution: :daily_mean,
      dates: dates,
      series:
        present_series(roster, fn plug ->
          Enum.map(dates, &mean_watts(row_by_plug_and_date[{plug.id, &1}]))
        end)
    }
  end

  defp mean_watts(nil), do: nil
  defp mean_watts(row), do: row.energy_wh / 24.0

  # One series per configured plug, dropping plugs without any value.
  defp present_series(roster, watts_fun) do
    for plug <- roster.all,
        watts = watts_fun.(plug),
        Enum.any?(watts, &(not is_nil(&1))),
        do: %{plug_id: plug.id, name: plug.name, role: plug.role, watts: watts}
  end

  defp rounded_kwh(energy), do: energy |> Amount.kwh() |> Float.round(3)
end
