defmodule Ziwoas.Rooms do
  @moduledoc """
  The rooms of the home and what stands in them (ADR-0014). Lamps and heaters carry a
  `room_id`; a plug from `ziwoas.yml` gets a `PlugRoom`. A device without a room stands under
  „Ohne Raum“. Deleting a room leaves its devices without one.
  """
  import Ecto.Changeset
  import Ecto.Query

  alias Ziwoas.Repo
  alias Ziwoas.Rooms.{PlugRoom, Room}

  @gone "Diesen Raum gibt es nicht mehr"

  @spec list() :: [Room.t()]
  def list, do: Repo.all(from r in Room, order_by: [r.position, r.id])

  @spec get(term) :: Room.t() | nil
  def get(id) when is_integer(id), do: Repo.get(Room, id)

  def get(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> Repo.get(Room, id)
      _not_an_id -> nil
    end
  end

  def get(_id), do: nil

  @spec change(Room.t(), map) :: Ecto.Changeset.t()
  def change(room \\ %Room{}, params \\ %{}), do: Room.changeset(room, params)

  @doc "Adds a room at the end of the order."
  @spec create(map) :: {:ok, Room.t()} | {:error, Ecto.Changeset.t()}
  def create(params) do
    position = Repo.one(from r in Room, select: coalesce(max(r.position), 0)) + 1
    %Room{position: position} |> Room.changeset(params) |> Repo.insert()
  end

  @spec rename(Room.t(), map) :: {:ok, Room.t()} | {:error, Ecto.Changeset.t()}
  def rename(room, params),
    do:
      room
      |> Room.changeset(params)
      |> Repo.update(stale_error_field: :name, stale_error_message: @gone)

  @spec delete(Room.t()) :: {:ok, Room.t()} | {:error, Ecto.Changeset.t()}
  def delete(room), do: Repo.delete(room, stale_error_field: :name, stale_error_message: @gone)

  @doc "Swaps the room with its neighbour above or below; at either end it stays."
  @spec move(Room.t(), :up | :down) :: :ok
  def move(room, direction) when direction in [:up, :down] do
    rooms = list()
    index = Enum.find_index(rooms, &(&1.id == room.id))
    other = if direction == :up, do: index && index - 1, else: index && index + 1

    if other in 0..(length(rooms) - 1)//1 do
      swap(Enum.at(rooms, index), Enum.at(rooms, other))
    end

    :ok
  end

  defp swap(room, neighbour) do
    Repo.transaction(fn ->
      Repo.update!(Ecto.Changeset.change(room, position: neighbour.position))
      Repo.update!(Ecto.Changeset.change(neighbour, position: room.position))
    end)
  end

  @doc "Refuses a `room_id` whose room is gone, e.g. deleted while a form was open."
  @spec validate_room(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_room(changeset) do
    validate_change(changeset, :room_id, fn :room_id, id ->
      if Repo.exists?(from r in Room, where: r.id == ^id),
        do: [],
        else: [room_id: @gone]
    end)
  end

  @doc "Each placed plug's room id, by plug id."
  @spec plug_rooms() :: %{String.t() => integer}
  def plug_rooms, do: Map.new(Repo.all(from p in PlugRoom, select: {p.plug_id, p.room_id}))

  @spec plug_room(String.t()) :: integer | nil
  def plug_room(plug_id),
    do: Repo.one(from p in PlugRoom, where: p.plug_id == ^plug_id, select: p.room_id)

  @doc "Puts the plug into the room; a blank room takes it out of any."
  @spec place_plug(String.t(), String.t() | integer | nil) ::
          {:ok, PlugRoom.t() | nil} | {:error, Ecto.Changeset.t()}
  def place_plug(plug_id, room_id) when room_id in [nil, ""] do
    Repo.delete_all(from p in PlugRoom, where: p.plug_id == ^plug_id)
    {:ok, nil}
  end

  def place_plug(plug_id, room_id) do
    %PlugRoom{plug_id: plug_id}
    |> cast(%{room_id: room_id}, [:room_id])
    |> validate_required([:room_id])
    |> validate_room()
    |> Repo.insert(
      on_conflict: {:replace, [:room_id, :updated_at]},
      conflict_target: :plug_id
    )
  end
end
