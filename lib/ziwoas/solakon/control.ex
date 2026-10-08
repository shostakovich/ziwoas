defmodule Ziwoas.Solakon.Control do
  @moduledoc false
  import Ecto.Query

  alias Ziwoas.Repo
  alias Ziwoas.Solakon.Control.{Decision, State}

  @cleared [decision_state: nil, trim: false, last_target_w: nil, last_decision_at: nil]

  @spec state() :: State.t()
  def state do
    case Repo.all(from(s in State, order_by: s.id, limit: 1)) do
      [state] -> state
      [] -> %State{}
    end
  end

  @spec state!() :: State.t()
  def state! do
    case state() do
      %State{id: nil} = state -> Repo.insert!(state)
      state -> state
    end
  end

  @spec pause!(State.t()) :: State.t()
  def pause!(state), do: update!(state, paused: true)

  @doc "Resumes the loop and forgets the last decision, so the next tick starts afresh."
  @spec resume!(State.t()) :: State.t()
  def resume!(state), do: update!(state, [paused: false] ++ @cleared)

  @spec store!(State.t(), Decision.t(), DateTime.t()) :: State.t()
  def store!(state, %Decision{} = decision, at),
    do:
      update!(state,
        decision_state: Atom.to_string(decision.state),
        trim: decision.trim,
        last_target_w: decision.target_w,
        last_decision_at: at
      )

  @spec clear!(State.t()) :: State.t()
  def clear!(state), do: update!(state, @cleared)

  @spec count_failure!(State.t()) :: State.t()
  def count_failure!(state),
    do: update!(state, consecutive_failures: state.consecutive_failures + 1)

  @spec reset_failures!(State.t()) :: State.t()
  def reset_failures!(%State{consecutive_failures: 0} = state), do: state
  def reset_failures!(state), do: update!(state, consecutive_failures: 0)

  defp update!(state, changes),
    do: state |> Ecto.Changeset.change(changes) |> Repo.update!()
end
