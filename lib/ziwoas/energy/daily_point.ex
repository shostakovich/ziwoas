defmodule Ziwoas.Energy.DailyPoint do
  @moduledoc "One day of the report. Uncovered days have no summary behind them."
  alias Ziwoas.Energy.Amount

  @enforce_keys [:date, :produced, :consumed, :self_consumed, :covered]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          date: Date.t(),
          produced: Amount.t(),
          consumed: Amount.t(),
          self_consumed: Amount.t(),
          covered: boolean
        }

  @spec uncovered(Date.t()) :: t
  def uncovered(%Date{} = date) do
    %__MODULE__{
      date: date,
      produced: Amount.zero(),
      consumed: Amount.zero(),
      self_consumed: Amount.zero(),
      covered: false
    }
  end

  @spec balance(t) :: Amount.t()
  def balance(%__MODULE__{produced: produced, consumed: consumed}),
    do: Amount.subtract(produced, consumed)
end
