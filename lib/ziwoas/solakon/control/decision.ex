defmodule Ziwoas.Solakon.Control.Decision do
  @moduledoc """
  What one control tick decided (Rails' `Solakon::Control::Decision`): the policy
  state, the target in whole watts (nil only when read back without one), and
  whether low-SoC trimming is running.
  """
  @states [:normal, :surplus, :surplus_exhausted, :probe, :probe_blocked, :protected]

  @enforce_keys [:state, :target_w, :trim]
  defstruct @enforce_keys

  @type state :: :normal | :surplus | :surplus_exhausted | :probe | :probe_blocked | :protected
  @type t :: %__MODULE__{state: state, target_w: integer | nil, trim: boolean}

  def states, do: @states

  @doc """
  The state as stored in `decision_state`. An unknown name raises, as Rails'
  enum type does: it would otherwise fall through the policy into `:normal`.
  """
  @spec state!(String.t() | atom) :: state
  def state!(name) when is_atom(name) and name in @states, do: name

  def state!(name) when is_binary(name) do
    Enum.find(@states, &(Atom.to_string(&1) == name)) ||
      raise ArgumentError, "unknown control state #{inspect(name)}"
  end
end

defmodule Ziwoas.Solakon.Control.Load do
  @moduledoc """
  The household load a tick regulates against (Rails' `Solakon::Control::Load`):
  the live sum of the consumer plugs, nil when none is online, and the guaranteed
  floor that stands in for it.
  """
  @enforce_keys [:current_w, :floor_w]
  defstruct @enforce_keys

  @type t :: %__MODULE__{current_w: float | nil, floor_w: float}

  @spec new(number | nil, number) :: t
  def new(current_w, floor_w),
    do: %__MODULE__{current_w: current_w && current_w * 1.0, floor_w: floor_w * 1.0}

  @spec effective_w(t) :: float
  def effective_w(%__MODULE__{current_w: nil, floor_w: floor_w}), do: floor_w
  def effective_w(%__MODULE__{current_w: current_w}), do: current_w
end
