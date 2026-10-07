defmodule Ziwoas.Economics.Overview do
  @moduledoc """
  The figures of the Wirtschaftlichkeit card (`Ziwoas.Economics.overview/1`).
  Without a price, the money figures are nil.
  """
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
end
