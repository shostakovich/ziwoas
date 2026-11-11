defmodule Ziwoas.Residents.Favourite do
  @moduledoc "A device a resident starred: a lamp or heater by its `key`, a plug by its `id`."
  use Ziwoas.Schema

  @type t :: %__MODULE__{}

  schema "favourites" do
    field :resident, :string
    field :kind, Ecto.Enum, values: [:lamp, :heater, :plug]
    field :device_id, :string
    timestamps()
  end
end
