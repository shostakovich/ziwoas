defmodule Ziwoas.Rooms.PlugRoom do
  @moduledoc "The room a plug from `ziwoas.yml` stands in; a plug without one has no row."
  use Ziwoas.Schema

  @type t :: %__MODULE__{}

  schema "plug_rooms" do
    field :plug_id, :string
    belongs_to :room, Ziwoas.Rooms.Room
    timestamps()
  end
end
