defmodule Ziwoas.Solakon.Control.State do
  @moduledoc """
  The single row of control state (`solakon_control_states`): whether the loop
  is paused, the last decision that actually reached the inverter, and the
  consecutive write failures. A row, not a cache: the policy regulates against
  what is stored here.
  """
  use Ziwoas.Schema

  import Ecto.Query

  alias Ziwoas.Repo
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

  @cleared [decision_state: nil, trim: false, last_target_w: nil, last_decision_at: nil]

  @doc """
  The row, or an unsaved default while there is none (reads only; a missing row
  reads as not paused).
  """
  @spec current() :: t
  def current do
    case Repo.all(from(s in __MODULE__, order_by: s.id, limit: 1)) do
      [state] -> state
      [] -> %__MODULE__{}
    end
  end

  @doc "The row, created on first use."
  @spec current!() :: t
  def current! do
    case current() do
      %__MODULE__{id: nil} = state -> Repo.insert!(state)
      state -> state
    end
  end

  @spec active?(t) :: boolean
  def active?(%__MODULE__{paused: paused}), do: not paused

  @spec pause!(t) :: t
  def pause!(state), do: update!(state, paused: true)

  @doc "Resumes the loop and forgets the last decision, so the next tick starts afresh."
  @spec resume!(t) :: t
  def resume!(state), do: update!(state, [paused: false] ++ @cleared)

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

  @spec store!(t, Decision.t(), DateTime.t()) :: t
  def store!(state, %Decision{} = decision, at),
    do:
      update!(state,
        decision_state: Atom.to_string(decision.state),
        trim: decision.trim,
        last_target_w: decision.target_w,
        last_decision_at: at
      )

  @spec clear!(t) :: t
  def clear!(state), do: update!(state, @cleared)

  @spec count_failure!(t) :: t
  def count_failure!(state),
    do: update!(state, consecutive_failures: state.consecutive_failures + 1)

  @spec reset_failures!(t) :: t
  def reset_failures!(%__MODULE__{consecutive_failures: 0} = state), do: state
  def reset_failures!(state), do: update!(state, consecutive_failures: 0)

  defp update!(state, changes),
    do: state |> Ecto.Changeset.change(changes) |> Repo.update!()
end
