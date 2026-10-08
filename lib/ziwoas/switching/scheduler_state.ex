defmodule Ziwoas.Switching.SchedulerState do
  @moduledoc false
  use Ziwoas.Schema

  schema "scheduler_states" do
    field :last_tick_at, :utc_datetime_usec
    field :plug_id, :string
    timestamps()
  end

  @type t :: %__MODULE__{}
end
