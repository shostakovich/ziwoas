defmodule Ziwoas.Solakon.Control.State do
  @moduledoc false
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
