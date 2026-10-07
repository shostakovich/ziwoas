defmodule Ziwoas.Energy do
  @moduledoc false
  import Ecto.Query

  alias Ziwoas.{Clock, Config, Economics, LocalDay, Plugs, Repo, Solakon}
  alias Ziwoas.Energy.{Amount, Balance, DailySummary, Flow, LiveState, PowerSeries, Report}
  alias Ziwoas.Plugs.{Measurement, Plug, Roster}
  alias Ziwoas.Solakon.Reading

  @spec today(Config.t(), DateTime.t()) :: Balance.t()
  def today(%Config{} = config, now \\ Clock.now()) do
    zone = config.location.timezone
    today = now |> DateTime.shift_zone!(zone) |> DateTime.to_date()
    {start_ts, end_ts} = LocalDay.window(today, zone)
    roster = Config.plug_roster(config)

    produced = Amount.wh(Plugs.energy_wh(Roster.producer_ids(roster), start_ts, end_ts))
    consumed = Amount.wh(Plugs.energy_wh(Roster.consumer_ids(roster), start_ts, end_ts))

    self_consumed =
      roster
      |> power_series(start_ts, end_ts, PowerSeries.sample_5min_bucket_seconds())
      |> PowerSeries.self_consumed_wh(produced.wh, consumed.wh)
      |> Amount.wh()

    %Balance{
      date: today,
      produced: produced,
      consumed: consumed,
      self_consumed: self_consumed,
      savings_eur: Economics.savings_eur(Economics.kwh_prices(), self_consumed, today)
    }
  end

  @spec autarky_ratio(%{self_consumed: Amount.t(), consumed: Amount.t()}) :: float
  def autarky_ratio(%{self_consumed: self_consumed, consumed: consumed}),
    do: Amount.ratio_to(self_consumed, consumed)

  @spec self_consumption_ratio(%{self_consumed: Amount.t(), produced: Amount.t()}) :: float
  def self_consumption_ratio(%{self_consumed: self_consumed, produced: produced}),
    do: Amount.ratio_to(self_consumed, produced)

  @spec live_state(Config.t(), DateTime.t(), keyword) :: LiveState.t()
  def live_state(%Config{} = config, now, opts \\ []) do
    offline_after_s = Keyword.get(opts, :offline_after_s, Measurement.offline_after_s())
    stale_after_s = Keyword.get(opts, :stale_after_s, Reading.stale_after_s())
    now = now |> DateTime.truncate(:second) |> DateTime.to_unix() |> DateTime.from_unix!()
    roster = Config.plug_roster(config)

    measurements = Plugs.latest_measurements(Roster.ids(roster), now, offline_after_s)

    reading =
      if config.solakon && config.solakon.monitoring_enabled,
        do: Solakon.fresh_reading(now, stale_after_s)

    %LiveState{
      plugs: Enum.map(roster.all, &live_row(&1, measurements[&1.id])),
      energy_flow:
        Flow.build(Measurement.total_w(measurements, Roster.consumer_ids(roster)), reading)
    }
  end

  defp live_row(plug, measurement) do
    %LiveState.Row{
      id: plug.id,
      name: plug.name,
      role: plug.role,
      online: not measurement.offline,
      apower_w: Measurement.reported_watt(measurement),
      last_seen_ts: measurement.last_seen_ts
    }
  end

  @spec power_series(Roster.t() | list, integer, integer, pos_integer) :: PowerSeries.t()
  def power_series(plugs, start_ts, end_ts, bucket_seconds) do
    roster = Roster.new(plugs)

    roster
    |> Roster.ids()
    |> Plugs.mean_power(start_ts, end_ts, bucket_seconds)
    |> PowerSeries.new(roster, bucket_seconds)
  end

  @spec power_by_plug(list, integer, integer, pos_integer) :: [{Plug.t(), [{integer, float}]}]
  def power_by_plug(plugs, start_ts, end_ts, bucket_seconds) do
    series = power_series(plugs, start_ts, end_ts, bucket_seconds)

    for plug <- plugs do
      points =
        series
        |> PowerSeries.signed_watts_by_ts(plug.id)
        |> Enum.sort_by(fn {ts, _watts} -> ts end)

      {plug, points}
    end
  end

  @spec summarize_day(Roster.t() | list, String.t(), Date.t()) :: DailySummary.t()
  def summarize_day(plugs, timezone, %Date{} = date) do
    roster = Roster.new(plugs)
    {start_ts, end_ts} = LocalDay.window(date, timezone)
    rows = Plugs.samples_5min(start_ts, end_ts)
    {produced_wh, consumed_wh} = metered_energy_wh(rows, roster)

    self_consumed_wh =
      rows
      |> PowerSeries.from_5min(roster)
      |> PowerSeries.self_consumed_wh(produced_wh, consumed_wh)

    Repo.insert!(
      %DailySummary{
        date: date,
        produced_wh: produced_wh * 1.0,
        consumed_wh: consumed_wh * 1.0,
        self_consumed_wh: self_consumed_wh * 1.0
      },
      on_conflict: :replace_all,
      conflict_target: :date
    )
  end

  defp metered_energy_wh(rows, roster) do
    Enum.reduce(rows, {0.0, 0.0}, fn row, {produced, consumed} ->
      case Roster.role_of(roster, row.plug_id) do
        :producer -> {produced + row.energy_delta_wh, consumed}
        :consumer -> {produced, consumed + row.energy_delta_wh}
        _ -> {produced, consumed}
      end
    end)
  end

  @spec daily_summaries(Date.t() | nil, Date.t() | nil) :: [DailySummary.t()]
  def daily_summaries(first \\ nil, last \\ nil) do
    DailySummary
    |> order_by(:date)
    |> between(first, last)
    |> Repo.all()
  end

  defp between(query, nil, nil), do: query

  defp between(query, %Date{} = first, %Date{} = last),
    do: where(query, [s], s.date >= ^first and s.date <= ^last)

  @spec report(Report.range(), keyword) :: Report.t()
  defdelegate report(range, opts), to: Report, as: :build
end
