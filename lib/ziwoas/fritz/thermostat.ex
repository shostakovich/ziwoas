defmodule Ziwoas.Fritz.Thermostat do
  @moduledoc false
  @enforce_keys [:key, :ain, :name, :present]
  defstruct @enforce_keys ++ [:measured_c, :target, :battery_pct, battery_low: false, busy: false]

  @type target :: {:heat, float} | :off | :on

  @typedoc "`busy`: a command is in transit, or an open window or a boost holds the target."
  @type t :: %__MODULE__{
          key: String.t(),
          ain: String.t(),
          name: String.t(),
          present: boolean,
          measured_c: float | nil,
          target: target | nil,
          battery_pct: non_neg_integer | nil,
          battery_low: boolean,
          busy: boolean
        }

  @doc "The AIN without its spaces: stable, and safe in URLs and DOM ids."
  @spec key(String.t()) :: String.t()
  def key(ain), do: String.replace(ain, " ", "")
end
