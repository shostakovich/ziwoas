defmodule Ziwoas.EnergyReport.DailyPoint do
  @moduledoc "One day of the report, in Wh. Uncovered days have no aggregate behind them."
  alias Ziwoas.Energy

  @enforce_keys [:date, :produced, :consumed, :self_consumed, :covered]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          date: String.t(),
          produced: Energy.t(),
          consumed: Energy.t(),
          self_consumed: Energy.t(),
          covered: boolean
        }

  @spec uncovered(String.t()) :: t
  def uncovered(date_s) do
    %__MODULE__{
      date: date_s,
      produced: Energy.zero(),
      consumed: Energy.zero(),
      self_consumed: Energy.zero(),
      covered: false
    }
  end

  @spec balance(t) :: Energy.t()
  def balance(%__MODULE__{produced: produced, consumed: consumed}),
    do: Energy.subtract(produced, consumed)
end
