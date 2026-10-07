defmodule Ziwoas.Switching.Command do
  @moduledoc "A switch command sent to a plug, from the schedule or by hand (`switch_commands`)."
  use Ziwoas.Schema

  @type action :: :on | :off
  @type source :: :manual | :schedule

  schema "switch_commands" do
    field :action, Ecto.Enum, values: [:on, :off]
    field :plug_id, :string
    field :source, Ecto.Enum, values: [:manual, :schedule]
    timestamps()
  end

  @type t :: %__MODULE__{}
end
