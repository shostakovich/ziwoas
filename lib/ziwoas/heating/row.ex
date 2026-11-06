defmodule Ziwoas.Heating.Row do
  @moduledoc false
  alias Ziwoas.Fritz.Thermostat
  alias Ziwoas.Heating.{Decision, Heater}
  alias Ziwoas.Switching.Schedule

  @enforce_keys [:heater, :entries, :decision, :thermostat, :now]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          heater: Heater.t(),
          entries: [Schedule.Window.t()],
          decision: Decision.t(),
          thermostat: Thermostat.t() | nil,
          now: DateTime.t()
        }

  @spec offline?(t) :: boolean
  def offline?(%__MODULE__{thermostat: %Thermostat{present: true}}), do: false
  def offline?(%__MODULE__{}), do: true

  @doc "What the thermostat was last set to heat, by ZiWoAS or by hand; else what is decided."
  @spec set_to_heat?(t) :: boolean
  def set_to_heat?(%__MODULE__{heater: heater, decision: %Decision{state: state}}),
    do: (Heater.written_state(heater) || state) == :heat

  @doc "Heating, as far as anyone can tell: set to heat and the thermostat reachable."
  @spec heating?(t) :: boolean
  def heating?(row), do: set_to_heat?(row) and not offline?(row)
end
