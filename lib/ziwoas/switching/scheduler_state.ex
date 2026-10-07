defmodule Ziwoas.Switching.SchedulerState do
  @moduledoc """
  When the scheduler last worked through a plug's edges (`scheduler_states`). One
  row per plug, so a failed switch only makes its own plug retry.
  """
  use Ziwoas.Schema

  schema "scheduler_states" do
    field :last_tick_at, :utc_datetime_usec
    field :plug_id, :string
    timestamps()
  end

  @type t :: %__MODULE__{}
end
