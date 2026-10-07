defmodule Ziwoas.EnergyReport do
  @moduledoc """
  The energy report over a range of aggregated days: totals and ratios, a
  ranking per role, and the chart payloads. Days are summed in Wh and rounded
  only where a number is shown, with Ruby's `Float#round`.
  """
  alias Ziwoas.{Economics, Energy, RubyDate, RubyNumeric}
  alias Ziwoas.Economics.SavingsCalculator
  alias Ziwoas.EnergyReport.{ChartBuilder, DailyPoint, Store}
  alias Ziwoas.Plugs.Roster

  defstruct [
    :start_date,
    :end_date,
    :selected_date,
    :preset,
    :summary,
    :daily_points,
    :producer_ranking,
    :consumer_ranking,
    :detail_start_date,
    :detail_end_date,
    :chart_payload,
    messages: []
  ]

  @type t :: %__MODULE__{}

  @default_preset "last_7"
  @preset_days %{"last_7" => 7, "last_30" => 30}
  @invalid_range_message "Der Datumsbereich war ungueltig und wurde auf die letzten 7 Tage zurueckgesetzt."

  @doc """
  Options: `:params` (string keys: `preset`, `start_date`, `end_date`,
  `selected_date`), `:plugs`, `:location` (weather overlays need its
  coordinates), `:today` (the date an empty report shows; dates without a
  year take it) and `:price_book` (default: the prices on record).
  """
  @spec build(keyword) :: t
  def build(opts) do
    params = Keyword.get(opts, :params, %{})
    roster = Roster.new(Keyword.fetch!(opts, :plugs))
    location = Keyword.fetch!(opts, :location)
    today = Keyword.fetch!(opts, :today)

    calculator =
      SavingsCalculator.new(Keyword.get_lazy(opts, :price_book, &Economics.price_book/0))

    case Store.latest_aggregate_date() do
      nil -> empty_report(today, calculator)
      latest -> report(params, latest, today, roster, location, calculator)
    end
  end

  @spec empty?(t) :: boolean
  def empty?(%__MODULE__{daily_points: points}), do: points == []

  defp report(params, latest, today, roster, location, calculator) do
    {%{start_date: first, end_date: last, preset: preset}, messages} =
      resolve_range(params, latest, today)

    rows = Store.daily_rows(first, last)
    daily_points = daily_points(Store.daily_summaries(first, last), first, last)

    %__MODULE__{
      start_date: first,
      end_date: last,
      selected_date: selected_date(params, first, last, today),
      preset: preset,
      summary: summarize(daily_points, calculator),
      daily_points: daily_points,
      producer_ranking: ranking(rows, roster, :producer),
      consumer_ranking: ranking(rows, roster, :consumer),
      detail_start_date: first,
      detail_end_date: last,
      chart_payload: ChartBuilder.payload(roster, location, daily_points, rows, {first, last}),
      messages: messages
    }
  end

  defp empty_report(today, calculator) do
    %__MODULE__{
      start_date: today,
      end_date: today,
      selected_date: today,
      preset: @default_preset,
      summary: empty_summary(calculator),
      daily_points: [],
      producer_ranking: [],
      consumer_ranking: [],
      detail_start_date: today,
      detail_end_date: today,
      chart_payload: %{
        daily: %{
          labels: [],
          produced_kwh: [],
          consumed_kwh: [],
          balance_kwh: [],
          consumer_series: [],
          ratios: []
        },
        detail: %{labels: [], series: []}
      }
    }
  end

  defp resolve_range(params, latest, today) do
    if present?(params["start_date"]) or present?(params["end_date"]) do
      with %Date{} = first <- RubyDate.iso8601(params["start_date"], today),
           %Date{} = last <- RubyDate.iso8601(params["end_date"], today),
           true <- Date.compare(first, last) != :gt do
        last = Enum.min([last, latest], Date)
        {%{start_date: Enum.min([first, last], Date), end_date: last, preset: "custom"}, []}
      else
        _ -> {preset_range(params, latest), [@invalid_range_message]}
      end
    else
      {preset_range(params, latest), []}
    end
  end

  defp preset_range(params, latest) do
    preset =
      if Map.has_key?(@preset_days, params["preset"]), do: params["preset"], else: @default_preset

    %{start_date: Date.add(latest, -(@preset_days[preset] - 1)), end_date: latest, preset: preset}
  end

  defp selected_date(params, first, last, today) do
    case RubyDate.iso8601(params["selected_date"], today) do
      %Date{} = date ->
        if Date.compare(date, first) != :lt and Date.compare(date, last) != :gt,
          do: date,
          else: last

      nil ->
        last
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp daily_points(summaries, first, last) do
    for date <- Date.range(first, last) do
      date_s = Date.to_iso8601(date)

      case summaries do
        %{^date_s => summary} ->
          %DailyPoint{
            date: date_s,
            produced: Energy.wh(summary.produced_wh),
            consumed: Energy.wh(summary.consumed_wh),
            self_consumed: Energy.wh(summary.self_consumed_wh),
            covered: true
          }

        _ ->
          DailyPoint.uncovered(date_s)
      end
    end
  end

  defp summarize(daily_points, calculator) do
    covered = Enum.filter(daily_points, & &1.covered)
    produced = covered |> Enum.map(& &1.produced) |> Energy.sum()
    consumed = covered |> Enum.map(& &1.consumed) |> Energy.sum()
    self_consumed = covered |> Enum.map(& &1.self_consumed) |> Energy.sum()
    days = length(covered)

    %{
      produced_kwh: rounded_kwh(produced),
      consumed_kwh: rounded_kwh(consumed),
      self_consumed_kwh: rounded_kwh(self_consumed),
      savings_eur: savings_eur(covered, calculator),
      balance_kwh: rounded_kwh(Energy.subtract(produced, consumed)),
      avg_produced_kwh: average_kwh(produced, days),
      avg_consumed_kwh: average_kwh(consumed, days),
      autarky_ratio: RubyNumeric.round(Energy.ratio_to(self_consumed, consumed), 4),
      self_consumption_ratio: RubyNumeric.round(Energy.ratio_to(self_consumed, produced), 4)
    }
  end

  defp empty_summary(calculator) do
    %{
      produced_kwh: 0.0,
      consumed_kwh: 0.0,
      self_consumed_kwh: 0.0,
      savings_eur: savings_eur([], calculator),
      balance_kwh: 0.0,
      avg_produced_kwh: 0.0,
      avg_consumed_kwh: 0.0,
      autarky_ratio: 0.0,
      self_consumption_ratio: 0.0
    }
  end

  # Each day carries the price in force on it, so a range spanning a price change isn't levelled.
  defp savings_eur(covered_points, calculator) do
    dated = Enum.map(covered_points, &{Date.from_iso8601!(&1.date), &1.self_consumed})

    case SavingsCalculator.total_eur(calculator, dated) do
      nil -> nil
      total -> RubyNumeric.round(total, 2)
    end
  end

  defp average_kwh(_total, 0), do: 0.0
  defp average_kwh(total, days), do: total |> Energy.divide(days) |> rounded_kwh()

  # position follows config order, the order the dashboard and charts colour plugs by.
  # Ties in kWh have no defined order (Rails' sort_by is unstable).
  defp ranking(rows, roster, role) do
    peers =
      if role == :producer, do: Roster.producer_ids(roster), else: Roster.consumer_ids(roster)

    rows = Enum.filter(rows, &(Roster.role_of(roster, &1.plug_id) == role))
    rows_by_plug = Enum.group_by(rows, & &1.plug_id)

    rows
    |> Enum.map(& &1.plug_id)
    |> Enum.uniq()
    |> Enum.map(fn plug_id ->
      %{
        plug_id: plug_id,
        name: Roster.find(roster, plug_id).name,
        role: Atom.to_string(role),
        position: Enum.find_index(peers, &(&1 == plug_id)),
        kwh:
          rows_by_plug[plug_id]
          |> Enum.map(& &1.energy_wh)
          |> RubyNumeric.sum()
          |> Energy.wh()
          |> rounded_kwh()
      }
    end)
    |> Enum.sort_by(& &1.kwh, :desc)
  end

  defp rounded_kwh(energy), do: energy |> Energy.kwh() |> RubyNumeric.round(3)
end
