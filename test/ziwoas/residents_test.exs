defmodule Ziwoas.ResidentsTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Residents, Rooms}

  defp room!(name) do
    {:ok, room} = Rooms.create(%{"name" => name})
    room
  end

  describe "favourites" do
    test "are kept per resident" do
      :ok = Residents.set_favourite("anna", {:lamp, "STEH"}, true)
      :ok = Residents.set_favourite("anna", {:plug, "fridge"}, true)
      :ok = Residents.set_favourite("ben", {:heater, "h1"}, true)

      assert Residents.favourites("anna") == MapSet.new([{:lamp, "STEH"}, {:plug, "fridge"}])
      assert Residents.favourites("ben") == MapSet.new([{:heater, "h1"}])
      assert Residents.favourite?("anna", {:lamp, "STEH"})
      refute Residents.favourite?("ben", {:lamp, "STEH"})
    end

    test "starring twice keeps one, removing takes it away" do
      :ok = Residents.set_favourite("anna", {:lamp, "STEH"}, true)
      :ok = Residents.set_favourite("anna", {:lamp, "STEH"}, true)
      assert Residents.favourites("anna") == MapSet.new([{:lamp, "STEH"}])

      :ok = Residents.set_favourite("anna", {:lamp, "STEH"}, false)
      :ok = Residents.set_favourite("anna", {:lamp, "STEH"}, false)
      assert Residents.favourites("anna") == MapSet.new()
    end

    test "no one has none" do
      assert Residents.favourites(nil) == MapSet.new()
      refute Residents.favourite?(nil, {:lamp, "STEH"})
    end
  end

  describe "the default view" do
    test "is „Alle“ until set, per resident" do
      room = room!("Büro")

      assert Residents.default_view("anna") == :all
      assert Residents.default_view(nil) == :all

      :ok = Residents.set_default_view("anna", {:room, room.id})
      :ok = Residents.set_default_view("ben", :favourites)

      assert Residents.default_view("anna") == {:room, room.id}
      assert Residents.default_view("ben") == :favourites

      :ok = Residents.set_default_view("anna", :favourites)
      assert Residents.default_view("anna") == :favourites

      :ok = Residents.set_default_view("anna", :all)
      assert Residents.default_view("anna") == :all
    end

    test "a deleted room takes the default along" do
      room = room!("Büro")
      :ok = Residents.set_default_view("anna", {:room, room.id})

      {:ok, _deleted} = Rooms.delete(room)

      assert Residents.default_view("anna") == :all
    end

    test "a room that is gone is refused" do
      assert Residents.set_default_view("anna", {:room, 999_999}) == {:error, :unknown_room}
      assert Residents.default_view("anna") == :all
    end
  end
end
