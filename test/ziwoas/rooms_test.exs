defmodule Ziwoas.RoomsTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Heating, Lights, Repo, Rooms}
  alias Ziwoas.Heating.Heater
  alias Ziwoas.Lights.Light
  alias Ziwoas.Rooms.Room

  defp errors_on(changeset),
    do: Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

  defp room!(name) do
    {:ok, room} = Rooms.create(%{"name" => name})
    room
  end

  describe "create/1" do
    test "appends rooms in order and trims the name" do
      room!("Küche")
      room!("  Bad ")

      assert Enum.map(Rooms.list(), &{&1.name, &1.position}) == [{"Küche", 1}, {"Bad", 2}]
    end

    test "refuses a blank or taken name in German" do
      room!("Bad")

      assert {:error, blank} = Rooms.create(%{"name" => "  "})
      assert "Gib dem Raum einen Namen" in errors_on(blank).name

      assert {:error, taken} = Rooms.create(%{"name" => "Bad"})
      assert "Diesen Raum gibt es schon" in errors_on(taken).name
    end
  end

  test "rename/2 keeps the place in the order" do
    room = room!("Büro")
    room!("Bad")

    assert {:ok, %Room{name: "Arbeitszimmer", position: 1}} =
             Rooms.rename(room, %{"name" => "Arbeitszimmer"})
  end

  test "rename/2 refuses a blank name instead of crashing" do
    room = room!("Büro")

    for blank <- ["", "   ", nil] do
      assert {:error, changeset} = Rooms.rename(room, %{"name" => blank})
      assert "Gib dem Raum einen Namen" in errors_on(changeset).name
    end

    assert Rooms.change(room, %{"name" => ""}).errors[:name]
  end

  test "get/1 finds a room by id and ignores anything else" do
    room = room!("Bad")

    assert Rooms.get(room.id).name == "Bad"
    assert Rooms.get(to_string(room.id)).name == "Bad"

    for junk <- ["abc", "#{room.id}x", "", nil, %{}, ["1"]],
        do: assert(Rooms.get(junk) == nil)
  end

  test "renaming or deleting a room that is gone is refused, not raised" do
    room = room!("Bad")
    {:ok, _deleted} = Rooms.delete(room)

    assert {:error, renamed} = Rooms.rename(room, %{"name" => "Badezimmer"})
    assert "Diesen Raum gibt es nicht mehr" in errors_on(renamed).name
    assert {:error, _deleted_twice} = Rooms.delete(room)
  end

  describe "move/2" do
    test "swaps a room with its neighbour" do
      kitchen = room!("Küche")
      bath = room!("Bad")
      bedroom = room!("Schlafzimmer")

      assert :ok = Rooms.move(bath, :up)
      assert Enum.map(Rooms.list(), & &1.name) == ["Bad", "Küche", "Schlafzimmer"]

      assert :ok = Rooms.move(kitchen, :down)
      assert Enum.map(Rooms.list(), & &1.name) == ["Bad", "Schlafzimmer", "Küche"]

      assert :ok = Rooms.move(bedroom, :up)
      assert Enum.map(Rooms.list(), & &1.name) == ["Schlafzimmer", "Bad", "Küche"]
    end

    test "leaves a room at either end where it is" do
      first = room!("Küche")
      last = room!("Bad")

      assert :ok = Rooms.move(Rooms.get(first.id), :up)
      assert :ok = Rooms.move(Rooms.get(last.id), :down)
      assert Enum.map(Rooms.list(), & &1.name) == ["Küche", "Bad"]
    end
  end

  describe "plugs" do
    test "place_plug/2 puts a plug into a room, moves it and takes it out" do
      kitchen = room!("Küche")
      bath = room!("Bad")

      assert {:ok, _placed} = Rooms.place_plug("kaffee", to_string(kitchen.id))
      assert Rooms.plug_room("kaffee") == kitchen.id

      assert {:ok, _moved} = Rooms.place_plug("kaffee", bath.id)
      assert Rooms.plug_rooms() == %{"kaffee" => bath.id}

      assert {:ok, nil} = Rooms.place_plug("kaffee", "")
      assert Rooms.plug_rooms() == %{}
    end

    test "place_plug/2 refuses a room that is gone" do
      assert {:error, changeset} = Rooms.place_plug("kaffee", 999)
      assert "Diesen Raum gibt es nicht mehr" in errors_on(changeset).room_id
    end
  end

  test "deleting a room leaves its devices without one" do
    room = room!("Wohnzimmer")
    light = Repo.insert!(%Light{key: "L1", name: "Uplighter", room_id: room.id})
    heater = Repo.insert!(%Heater{key: "H1", ain: "1", name: "Wohnzimmer", room_id: room.id})
    {:ok, _placed} = Rooms.place_plug("tv", room.id)

    assert {:ok, _deleted} = Rooms.delete(room)

    assert Repo.reload!(light).room_id == nil
    assert Repo.reload!(heater).room_id == nil
    assert Rooms.plug_rooms() == %{}
  end

  test "lamps and heaters take a room through their changesets" do
    room = room!("Bad")
    light = Repo.insert!(%Light{key: "L1", name: "Spiegel"})
    heater = Repo.insert!(%Heater{key: "H1", ain: "1", name: "Bad"})

    assert {:ok, %Light{room_id: room_id}} =
             Lights.update_settings(light, %{"name" => "Spiegel", "room_id" => room.id})

    assert room_id == room.id
    assert {:ok, %Heater{room_id: ^room_id}} = Heating.put_room(heater, %{"room_id" => room.id})
    assert {:ok, %Heater{room_id: nil}} = Heating.put_room(heater, %{"room_id" => ""})
    assert {:error, changeset} = Heating.put_room(heater, %{"room_id" => 999})
    assert "Diesen Raum gibt es nicht mehr" in errors_on(changeset).room_id
  end
end
