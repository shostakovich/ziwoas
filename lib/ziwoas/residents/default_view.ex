defmodule Ziwoas.Residents.DefaultView do
  @moduledoc "The view Schalten opens with for a resident; without a row it is „Alle“."
  use Ziwoas.Schema

  @type t :: %__MODULE__{}

  schema "default_views" do
    field :resident, :string
    field :view, Ecto.Enum, values: [:favourites, :room]
    belongs_to :room, Ziwoas.Rooms.Room
    timestamps()
  end
end
