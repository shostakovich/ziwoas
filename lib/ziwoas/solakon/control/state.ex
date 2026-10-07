defmodule Ziwoas.Solakon.Control.State do
  @moduledoc """
  The single row of control state (`solakon_control_states`): whether the loop
  is paused, the last decision that actually reached the inverter, and the
  consecutive write failures. A row, not a cache: the policy regulates against
  what is stored here. `Ziwoas.Solakon.Control` reads and writes it.
  """
  use Ziwoas.Schema

  alias Ziwoas.Solakon.Control.Decision

  @type t :: %__MODULE__{}

  schema "solakon_control_states" do
    field :consecutive_failures, :integer, default: 0
    field :decision_state, :string
    field :last_decision_at, :utc_datetime_usec
    field :last_target_w, :integer
    field :paused, :boolean, default: false
    field :trim, :boolean, default: false
    timestamps()
  end

  @spec active?(t) :: boolean
  def active?(%__MODULE__{paused: paused}), do: not paused

  @doc "The last written decision and when, or nil before the first one."
  @spec stored(t) :: {Decision.t(), DateTime.t()} | nil
  def stored(%__MODULE__{decision_state: name, last_decision_at: at})
      when name in [nil, ""] or is_nil(at),
      do: nil

  def stored(%__MODULE__{} = state) do
    {%Decision{
       state: Decision.state!(state.decision_state),
       target_w: state.last_target_w,
       trim: state.trim
     }, state.last_decision_at}
  end
end
