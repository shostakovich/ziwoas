defmodule Ziwoas.Energy.Amount do
  @moduledoc """
  An amount of energy. Watt-hours are canonical: everything is summed,
  subtracted and compared in Wh, and kilowatt-hours are a display conversion
  the caller rounds itself.
  """
  @enforce_keys [:wh]
  defstruct [:wh]

  @type t :: %__MODULE__{wh: float}

  @spec wh(number) :: t
  def wh(value) when is_number(value), do: %__MODULE__{wh: :erlang.float(value)}

  @spec zero() :: t
  def zero, do: wh(0.0)

  @doc "The empty sum is 0.0 Wh."
  @spec sum([t]) :: t
  def sum(energies), do: energies |> Enum.map(& &1.wh) |> Enum.sum() |> wh()

  @spec kwh(t) :: float
  def kwh(%__MODULE__{wh: wh}), do: wh / 1000.0

  @spec add(t, t) :: t
  def add(%__MODULE__{wh: a}, %__MODULE__{wh: b}), do: wh(a + b)

  @spec subtract(t, t) :: t
  def subtract(%__MODULE__{wh: a}, %__MODULE__{wh: b}), do: wh(a - b)

  @spec divide(t, number) :: t
  def divide(%__MODULE__{wh: a}, divisor), do: wh(a / divisor)

  @spec zero?(t) :: boolean
  def zero?(%__MODULE__{wh: wh}), do: wh == 0.0

  @doc "-0.0 Wh is not negative."
  @spec negative?(t) :: boolean
  def negative?(%__MODULE__{wh: wh}), do: wh < 0.0

  @spec ratio_to(t, t) :: float
  def ratio_to(%__MODULE__{wh: a}, %__MODULE__{} = other),
    do: if(zero?(other), do: 0.0, else: a / other.wh)
end
