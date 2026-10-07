defmodule Ziwoas.Solakon.Control.Decision do
  @moduledoc false
  @states [:normal, :surplus, :surplus_exhausted, :probe, :probe_blocked, :protected]

  @enforce_keys [:state, :target_w, :trim]
  defstruct @enforce_keys

  @type state :: :normal | :surplus | :surplus_exhausted | :probe | :probe_blocked | :protected
  @type t :: %__MODULE__{state: state, target_w: integer | nil, trim: boolean}

  def states, do: @states

  @doc "An unknown name raises rather than falling through the policy into `:normal`."
  @spec state!(String.t() | atom) :: state
  def state!(name) when is_atom(name) and name in @states, do: name

  def state!(name) when is_binary(name) do
    Enum.find(@states, &(Atom.to_string(&1) == name)) ||
      raise ArgumentError, "unknown control state #{inspect(name)}"
  end
end

defmodule Ziwoas.Solakon.Control.Load do
  @moduledoc false
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
