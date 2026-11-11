defmodule Ziwoas.Residents do
  @moduledoc """
  What ZiWoAS keeps per resident (ADR-0016, ADR-0017): the devices they starred and the view
  Schalten opens with. A resident is the login name the gate reports; `nil` is no one, who has
  no favourites and opens with „Alle“.
  """
  import Ecto.Query

  alias Ziwoas.Repo
  alias Ziwoas.Residents.{DefaultView, Favourite}
  alias Ziwoas.Rooms

  @type device :: {:lamp | :heater | :plug, String.t()}
  @type view :: :all | :favourites | {:room, pos_integer}

  @spec favourites(String.t() | nil) :: MapSet.t(device)
  def favourites(nil), do: MapSet.new()

  def favourites(resident) do
    from(f in Favourite, where: f.resident == ^resident, select: {f.kind, f.device_id})
    |> Repo.all()
    |> MapSet.new()
  end

  @spec favourite?(String.t() | nil, device) :: boolean
  def favourite?(nil, _device), do: false

  def favourite?(resident, {kind, device_id}),
    do: Repo.exists?(favourite_query(resident, kind, device_id))

  @doc "Stars the device for the resident, or takes the star away."
  @spec set_favourite(String.t(), device, boolean) :: :ok
  def set_favourite(resident, {kind, device_id}, true) when is_binary(resident) do
    Repo.insert!(%Favourite{resident: resident, kind: kind, device_id: device_id},
      on_conflict: :nothing,
      conflict_target: [:resident, :kind, :device_id]
    )

    :ok
  end

  def set_favourite(resident, {kind, device_id}, false) when is_binary(resident) do
    Repo.delete_all(favourite_query(resident, kind, device_id))
    :ok
  end

  defp favourite_query(resident, kind, device_id),
    do:
      from(f in Favourite,
        where: f.resident == ^resident and f.kind == ^kind and f.device_id == ^device_id
      )

  @doc "The view the resident set; a deleted room took its row along, so it reads as „Alle“."
  @spec default_view(String.t() | nil) :: view
  def default_view(nil), do: :all

  def default_view(resident) do
    case Repo.get_by(DefaultView, resident: resident) do
      nil -> :all
      %DefaultView{view: :favourites} -> :favourites
      %DefaultView{view: :room, room_id: room_id} -> {:room, room_id}
    end
  end

  @doc "Makes `view` the resident's default; „Alle“ needs no row."
  @spec set_default_view(String.t(), view) :: :ok | {:error, :unknown_room}
  def set_default_view(resident, :all) when is_binary(resident) do
    Repo.delete_all(from d in DefaultView, where: d.resident == ^resident)
    :ok
  end

  def set_default_view(resident, :favourites) when is_binary(resident),
    do: upsert_default(resident, :favourites, nil)

  def set_default_view(resident, {:room, room_id}) when is_binary(resident) do
    case Rooms.get(room_id) do
      nil -> {:error, :unknown_room}
      room -> upsert_default(resident, :room, room.id)
    end
  end

  defp upsert_default(resident, view, room_id) do
    Repo.insert!(%DefaultView{resident: resident, view: view, room_id: room_id},
      on_conflict: {:replace, [:view, :room_id, :updated_at]},
      conflict_target: :resident
    )

    :ok
  end
end
