defmodule Ziwoas.Economics.Overview do
  @moduledoc """
  Everything the Wirtschaftlichkeit card shows, read once: the daily
  self-consumption on record, priced day by day, against what the plant cost.
  Without a price, the money figures are unknown (nil), not zero.
  """
  import Ecto.Query

  alias Ziwoas.{Economics, Energy, Repo}
  alias Ziwoas.Economics.{Payback, SavingsCalculator}
  alias Ziwoas.EnergyReport.DailyEnergySummary

  defstruct [
    :saved_eur,
    :acquisition_cost_eur,
    :covered_ratio,
    :data_start,
    :projected_payback_date,
    :reached_on,
    :projection_days,
    :priced,
    :costed
  ]

  @type t :: %__MODULE__{}

  @spec reached?(t) :: boolean
  def reached?(%__MODULE__{reached_on: reached_on}), do: not is_nil(reached_on)

  @spec build(Date.t()) :: t
  def build(%Date{} = today) do
    calculator = SavingsCalculator.new(Economics.price_book())
    priced = SavingsCalculator.priced?(calculator)
    summaries = Repo.all(from s in DailyEnergySummary, order_by: s.date)
    cost = Economics.total_cost_eur()
    payback = Payback.new(cost, daily_savings(summaries, calculator, priced), today)

    %__MODULE__{
      saved_eur: if(priced, do: Payback.saved_eur(payback)),
      acquisition_cost_eur: cost,
      covered_ratio: if(priced, do: Payback.covered_ratio(payback)),
      data_start: first_date(summaries),
      projected_payback_date: if(priced, do: Payback.projected_date(payback)),
      reached_on: if(priced, do: Payback.reached_on(payback)),
      projection_days: Payback.projection_days(payback),
      priced: priced,
      costed: Payback.costed?(payback)
    }
  end

  defp first_date([first | _]), do: Date.from_iso8601!(first.date)
  defp first_date([]), do: nil

  defp daily_savings(_summaries, _calculator, false), do: []

  defp daily_savings(summaries, calculator, true) do
    Enum.map(summaries, fn summary ->
      date = Date.from_iso8601!(summary.date)
      {date, SavingsCalculator.savings_eur(calculator, Energy.wh(summary.self_consumed_wh), date)}
    end)
  end
end
