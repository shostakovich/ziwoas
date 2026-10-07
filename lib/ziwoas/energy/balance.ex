defmodule Ziwoas.Energy.Balance do
  @moduledoc """
  A day's energy balance (`Ziwoas.Energy.today/2`): what the producers made
  and the consumers drew, the share of it consumed at the same time, and what
  that saved at the day's price (nil without a price on record).
  """
  alias Ziwoas.Energy.Amount

  @enforce_keys [:date, :produced, :consumed, :self_consumed, :savings_eur]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          date: Date.t(),
          produced: Amount.t(),
          consumed: Amount.t(),
          self_consumed: Amount.t(),
          savings_eur: float | nil
        }
end
