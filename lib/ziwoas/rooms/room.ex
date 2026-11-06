defmodule Ziwoas.Rooms.Room do
  @moduledoc "A room of the home; Schalten groups its lamps, heaters and plugs by it, in `position` order."
  use Ziwoas.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "rooms" do
    field :name, :string
    field :position, :integer
    timestamps()
  end

  @spec changeset(t, map) :: Ecto.Changeset.t()
  def changeset(room, params) do
    room
    |> cast(params, [:name])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> validate_required([:name], message: "Gib dem Raum einen Namen")
    |> validate_length(:name, max: 40, message: "Höchstens %{count} Zeichen")
    |> unique_constraint(:name, message: "Diesen Raum gibt es schon")
  end
end
