defmodule Ziwoas.Economics.Payback do
  @moduledoc """
  How far the savings have carried the plant towards its acquisition cost, and
  when they will have covered it. Every figure rests on the days actually on
  record: savings before the data start are never estimated, so the payback is
  reckoned late rather than early.
  """
  # Below this many days on record a projection says more about the season
  # than about the plant, so none is made.
  @min_projection_days 90
  # A full year levels out the seasons; a shorter record uses everything it has.
  @projection_window_days 365

  @enforce_keys [:cost, :days, :today]
  defstruct @enforce_keys

  @type t :: %__MODULE__{cost: float, days: [{Date.t(), float}], today: Date.t()}

  @spec new(number, [{Date.t(), number}], Date.t()) :: t
  def new(acquisition_cost_eur, daily_savings, %Date{} = today) do
    %__MODULE__{
      cost: acquisition_cost_eur,
      days: Enum.sort_by(daily_savings, &elem(&1, 0), Date),
      today: today
    }
  end

  @spec costed?(t) :: boolean
  def costed?(%__MODULE__{cost: cost}), do: cost > 0

  @spec saved_eur(t) :: number
  def saved_eur(%__MODULE__{days: days}), do: days |> Enum.map(&elem(&1, 1)) |> sum()

  @spec data_start(t) :: Date.t() | nil
  def data_start(%__MODULE__{days: [{date, _} | _]}), do: date
  def data_start(%__MODULE__{days: []}), do: nil

  @spec covered_ratio(t) :: float | nil
  def covered_ratio(payback) do
    if costed?(payback), do: min(saved_eur(payback) / payback.cost, 1.0)
  end

  @spec reached?(t) :: boolean
  def reached?(payback), do: costed?(payback) and saved_eur(payback) >= payback.cost

  @doc """
  The day the running total first reached the cost.
  """
  @spec reached_on(t) :: Date.t() | nil
  def reached_on(%__MODULE__{} = payback) do
    if reached?(payback), do: first_reaching_day(payback.days, 0.0, payback.cost)
  end

  defp first_reaching_day([], _running, _cost), do: nil

  defp first_reaching_day([{date, eur} | rest], running, cost) do
    running = running + eur
    if running >= cost, do: date, else: first_reaching_day(rest, running, cost)
  end

  @spec projection_days(t) :: non_neg_integer
  def projection_days(payback), do: payback |> projection_window() |> length()

  @spec projected_date(t) :: Date.t() | nil
  def projected_date(%__MODULE__{} = payback) do
    with true <- costed?(payback) and not reached?(payback),
         true <- projection_days(payback) >= @min_projection_days,
         rate when rate > 0 <- average_daily_eur(payback) do
      Date.add(payback.today, ceil((payback.cost - saved_eur(payback)) / rate))
    else
      _ -> nil
    end
  end

  defp projection_window(%__MODULE__{days: days, today: today}) do
    cutoff = Date.add(today, -(@projection_window_days - 1))
    Enum.filter(days, fn {date, _eur} -> Date.compare(date, cutoff) != :lt end)
  end

  defp average_daily_eur(payback) do
    window = projection_window(payback)
    sum(Enum.map(window, &elem(&1, 1))) / length(window)
  end

  defp sum(values), do: Enum.reduce(values, 0.0, &+/2)
end
