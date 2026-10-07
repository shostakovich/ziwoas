defmodule Ziwoas.Govee.StateStoreTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Govee.StateStore

  @key "K"

  defp store, do: StateStore.new(5.0)

  defp commanded(changes, at \\ 100.0) do
    {_published, store} = StateStore.record_command(store(), @key, changes, at)
    store
  end

  test "an unknown lamp has neither a published state nor a status" do
    assert StateStore.published(store(), @key) == nil
    assert StateStore.status(store(), @key) == nil
  end

  test "a command publishes optimistically and stays pending" do
    {published, store} =
      StateStore.record_command(store(), @key, %{on: true, brightness: 40}, 1.0)

    assert published == %{on: true, brightness: 40}
    assert StateStore.published(store, @key) == published
    assert StateStore.status(store, @key) == :pending
  end

  test "commands merge into what was published; nil clears a field" do
    store = commanded(%{on: true, color_temp_k: 2700})

    {published, _store} =
      StateStore.record_command(
        store,
        @key,
        %{color: %{r: 1, g: 2, b: 3}, color_temp_k: nil},
        101.0
      )

    assert published == %{on: true, color: %{r: 1, g: 2, b: 3}, color_temp_k: nil}
  end

  describe "within the pending window" do
    test "a reading that matches confirms" do
      {result, store} =
        StateStore.apply_telemetry(
          commanded(%{on: true, brightness: 40}),
          @key,
          %{on: true, brightness: 40, reachable: true},
          :lan,
          102.0
        )

      assert result == %{
               published: %{on: true, brightness: 40, reachable: true},
               changed: true,
               needs_api_clarification: false
             }

      assert StateStore.status(store, @key) == :synced
    end

    test "a reading that deviates is the lamp not having applied it yet" do
      store = commanded(%{on: true, brightness: 40})

      for source <- [:lan, :api] do
        {result, after_reading} =
          StateStore.apply_telemetry(store, @key, %{on: true, brightness: 10}, source, 104.9)

        assert result == %{
                 published: %{on: true, brightness: 40},
                 changed: false,
                 needs_api_clarification: false
               }

        assert StateStore.status(after_reading, @key) == :pending
      end
    end

    test "a field the reading lacks is no deviation" do
      {result, _store} =
        StateStore.apply_telemetry(
          commanded(%{on: true, brightness: 40}),
          @key,
          %{on: true},
          :lan,
          101.0
        )

      assert result.published == %{on: true, brightness: 40}
      refute result.changed
    end
  end

  describe "after the window" do
    test "off is adopted at once" do
      {result, store} =
        StateStore.apply_telemetry(
          commanded(%{on: true, brightness: 40}),
          @key,
          %{on: false},
          :lan,
          105.0
        )

      assert result.published == %{on: false, brightness: 40}
      assert result.changed
      refute result.needs_api_clarification
      assert StateStore.status(store, @key) == :synced
    end

    test "a deviating LAN reading asks the API and changes nothing yet" do
      {result, store} =
        StateStore.apply_telemetry(
          commanded(%{on: true, brightness: 40}),
          @key,
          %{on: true, brightness: 10},
          :lan,
          106.0
        )

      assert result == %{
               published: %{on: true, brightness: 40},
               changed: false,
               needs_api_clarification: true
             }

      assert StateStore.status(store, @key) == :reconciling
    end

    test "the API is the truth" do
      store = commanded(%{on: true, brightness: 40})

      {_result, store} =
        StateStore.apply_telemetry(store, @key, %{on: true, brightness: 10}, :lan, 106.0)

      {result, store} =
        StateStore.apply_telemetry(store, @key, %{on: true, brightness: 10}, :api, 107.0)

      assert result.published == %{on: true, brightness: 10}
      assert result.changed
      assert StateStore.status(store, @key) == :synced
    end

    test "a matching reading changes nothing" do
      {result, _store} =
        StateStore.apply_telemetry(commanded(%{on: true}), @key, %{on: true}, :lan, 200.0)

      refute result.changed
      refute result.needs_api_clarification
    end
  end

  test "a lamp first heard on: the LAN asks the API, the API is adopted" do
    {result, _store} = StateStore.apply_telemetry(store(), @key, %{on: true}, :lan, 0.0)
    assert result == %{published: %{}, changed: false, needs_api_clarification: true}

    {result, store} =
      StateStore.apply_telemetry(store(), @key, %{on: true, reachable: true}, :api, 0.0)

    assert result.changed
    assert StateStore.published(store, @key) == %{on: true, reachable: true}
  end

  test "a lamp first heard off is adopted from the LAN" do
    {result, _store} =
      StateStore.apply_telemetry(store(), @key, %{on: false, reachable: true}, :lan, 0.0)

    assert result == %{
             published: %{on: false, reachable: true},
             changed: true,
             needs_api_clarification: false
           }
  end

  test "lamps are kept apart" do
    {_published, store} = StateStore.record_command(store(), "A", %{on: true}, 1.0)
    {_published, store} = StateStore.record_command(store, "B", %{on: false}, 1.0)

    assert StateStore.published(store, "A") == %{on: true}
    assert StateStore.published(store, "B") == %{on: false}
  end
end
