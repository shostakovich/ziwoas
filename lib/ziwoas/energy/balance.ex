defmodule Ziwoas.Energy.Balance do
  @moduledoc false
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
