defmodule Ziwoas.Switching.SchedulerState do
  @moduledoc """
  When the scheduler last worked through a plug's edges (`scheduler_states`). One
  row per plug, so a failed switch only makes its own plug retry.
  """
  use Ziwoas.Schema

  alias Ziwoas.Repo

  schema "scheduler_states" do
    field :last_tick_at, Ziwoas.Ecto.RailsDateTime
    field :plug_id, :string
    timestamps()
  end

  @spec last_tick_at(String.t()) :: DateTime.t() | nil
  def last_tick_at(plug_id) do
    case Repo.get_by(__MODULE__, plug_id: plug_id) do
      nil -> nil
      state -> state.last_tick_at
    end
  end

  @doc "`find_or_initialize_by(plug_id).update!(last_tick_at:)`: no write when nothing changes."
  @spec advance!(String.t(), DateTime.t()) :: t when t: %__MODULE__{}
  def advance!(plug_id, time) do
    (Repo.get_by(__MODULE__, plug_id: plug_id) || %__MODULE__{plug_id: plug_id})
    |> Ecto.Changeset.change(last_tick_at: time)
    |> Repo.insert_or_update!()
  end
end
