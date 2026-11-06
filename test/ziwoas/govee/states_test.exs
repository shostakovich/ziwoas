defmodule Ziwoas.Govee.StatesTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Govee.States

  @key "K"

  defp store, do: States.new(5.0)

  defp commanded(changes, at \\ 100.0) do
    {_published, store} = States.record_command(store(), @key, changes, at)
    store
  end

  test "an unknown lamp has neither a published state nor a status" do
    assert States.published(store(), @key) == nil
    assert States.status(store(), @key) == nil
  end

  test "a command publishes optimistically and stays pending" do
    {published, store} =
      States.record_command(store(), @key, %{on: true, brightness: 40}, 1.0)

    assert published == %{on: true, brightness: 40}
    assert States.published(store, @key) == published
    assert States.status(store, @key) == :pending
  end

  test "commands merge into what was published; nil clears a field" do
    store = commanded(%{on: true, color_temp_k: 2700})

    {published, _store} =
      States.record_command(
        store,
        @key,
        %{color: %{r: 1, g: 2, b: 3}, color_temp_k: nil},
        101.0
      )

    assert published == %{on: true, color: %{r: 1, g: 2, b: 3}, color_temp_k: nil}
  end

  describe "a LAN reading within the pending window" do
    test "that matches confirms" do
      {result, store} =
        States.apply_lan(
          commanded(%{on: true, brightness: 40}),
          @key,
          %{on: true, brightness: 40, reachable: true},
          102.0
        )

      assert result == %{published: %{on: true, brightness: 40, reachable: true}, changed: true}
      assert States.status(store, @key) == :synced
    end

    test "that deviates is the lamp not having applied it yet" do
      {result, store} =
        States.apply_lan(commanded(%{on: true, brightness: 40}), @key, %{on: false}, 104.9)

      assert result == %{published: %{on: true, brightness: 40}, changed: false}
      assert States.status(store, @key) == :pending
    end

    test "lacking a field does not deviate in it" do
      {result, _store} =
        States.apply_lan(commanded(%{on: true, brightness: 40}), @key, %{on: true}, 101.0)

      assert result == %{published: %{on: true, brightness: 40}, changed: false}
    end
  end

  describe "a LAN reading after the window" do
    test "is adopted as the lamp reports it" do
      {result, store} =
        States.apply_lan(
          commanded(%{on: true, brightness: 40}),
          @key,
          %{on: true, brightness: 10, color_temp_k: 2700},
          105.0
        )

      assert result == %{
               published: %{on: true, brightness: 10, color_temp_k: 2700},
               changed: true
             }

      assert States.status(store, @key) == :synced
    end

    test "that matches changes nothing" do
      {result, _store} = States.apply_lan(commanded(%{on: true}), @key, %{on: true}, 200.0)
      refute result.changed
    end
  end

  test "a lamp's first LAN reading is adopted" do
    {result, _store} = States.apply_lan(store(), @key, %{on: true, reachable: true}, 0.0)
    assert result == %{published: %{on: true, reachable: true}, changed: true}
  end

  describe "a cloud answer for a lamp heard on the LAN" do
    test "fills in only the zone states" do
      {_result, store} = States.apply_lan(store(), @key, %{on: true, reachable: true}, 0.0)

      {result, _store} =
        States.apply_api(
          store,
          @key,
          %{on: false, reachable: false, brightness: 70, zone_states: %{"z" => true}},
          :heard,
          1.0
        )

      assert result == %{
               published: %{on: true, reachable: true, zone_states: %{"z" => true}},
               changed: true
             }
    end

    test "within the pending window changes nothing" do
      {result, store} =
        States.apply_api(
          commanded(%{zone_states: %{"z" => true}}),
          @key,
          %{zone_states: %{"z" => false}},
          :heard,
          101.0
        )

      assert result == %{published: %{zone_states: %{"z" => true}}, changed: false}
      assert States.status(store, @key) == :pending
    end

    test "without zone states changes nothing" do
      {result, _store} =
        States.apply_api(commanded(%{on: true}), @key, %{on: false}, :heard, 200.0)

      assert result == %{published: %{on: true}, changed: false}
    end
  end

  describe "a cloud answer for a lamp not heard on the LAN" do
    test "is adopted in full, its reachability too" do
      {result, store} =
        States.apply_api(
          commanded(%{on: true, brightness: 40}),
          @key,
          %{on: false, reachable: false, zone_states: %{"z" => false}},
          :not_heard,
          106.0
        )

      assert result == %{
               published: %{
                 on: false,
                 reachable: false,
                 brightness: 40,
                 zone_states: %{"z" => false}
               },
               changed: true
             }

      assert States.status(store, @key) == :synced
    end

    test "that deviates within the pending window is ignored" do
      {result, _store} =
        States.apply_api(commanded(%{on: true}), @key, %{on: false}, :not_heard, 101.0)

      assert result == %{published: %{on: true}, changed: false}
    end
  end

  test "lamps are kept apart" do
    {_published, store} = States.record_command(store(), "A", %{on: true}, 1.0)
    {_published, store} = States.record_command(store, "B", %{on: false}, 1.0)

    assert States.published(store, "A") == %{on: true}
    assert States.published(store, "B") == %{on: false}
  end
end
