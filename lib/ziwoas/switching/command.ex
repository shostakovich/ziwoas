defmodule Ziwoas.Switching.Command do
  @moduledoc false
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
