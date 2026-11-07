defmodule Ziwoas.Solakon.Control.State do
  @moduledoc false
  use Ziwoas.Schema

  import Ecto.Changeset

  alias Ziwoas.Solakon.Control.Decision
  alias Ziwoas.Solakon.Reading

  @type t :: %__MODULE__{}

  schema "solakon_control_states" do
    field :consecutive_failures, :integer, default: 0
    field :decision_state, :string
    field :last_decision_at, :utc_datetime_usec
    field :last_target_w, :integer
    field :min_soc_pct, :integer, default: Reading.default_min_soc_pct()
    field :paused, :boolean, default: false
    field :trim, :boolean, default: false
    timestamps()
  end

  @doc "The minimum charge the control holds the battery at, edited from the PV page."
  @spec min_soc_changeset(t, map) :: Ecto.Changeset.t()
  def min_soc_changeset(state, attrs) do
    first..last//_ = Reading.min_soc_range()
    message = "Mindestladung zwischen #{first} und #{last} % angeben"

    state
    # No empty values: an emptied field would otherwise cast to the default and save silently.
    |> cast(attrs, [:min_soc_pct], empty_values: [], message: fn _field, _meta -> message end)
    |> validate_required(:min_soc_pct, message: message)
    |> validate_number(:min_soc_pct,
      greater_than_or_equal_to: first,
      less_than_or_equal_to: last,
      message: message
    )
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
