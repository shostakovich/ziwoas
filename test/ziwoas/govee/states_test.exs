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

  describe "within the pending window" do
    test "a reading that matches confirms" do
      {result, store} =
        States.apply_telemetry(
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

      assert States.status(store, @key) == :synced
    end

    test "a reading that deviates is the lamp not having applied it yet" do
      store = commanded(%{on: true, brightness: 40})

      for source <- [:lan, :api] do
        {result, after_reading} =
          States.apply_telemetry(store, @key, %{on: true, brightness: 10}, source, 104.9)

        assert result == %{
                 published: %{on: true, brightness: 40},
                 changed: false,
                 needs_api_clarification: false
               }

        assert States.status(after_reading, @key) == :pending
      end
    end

    test "a field the reading lacks is no deviation" do
      {result, _store} =
        States.apply_telemetry(
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
        States.apply_telemetry(
          commanded(%{on: true, brightness: 40}),
          @key,
          %{on: false},
          :lan,
          105.0
        )

      assert result.published == %{on: false, brightness: 40}
      assert result.changed
      refute result.needs_api_clarification
      assert States.status(store, @key) == :synced
    end

    test "a deviating LAN reading asks the API and changes nothing yet" do
      {result, store} =
        States.apply_telemetry(
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

      assert States.status(store, @key) == :reconciling
    end

    test "the API is the truth" do
      store = commanded(%{on: true, brightness: 40})

      {_result, store} =
        States.apply_telemetry(store, @key, %{on: true, brightness: 10}, :lan, 106.0)

      {result, store} =
        States.apply_telemetry(store, @key, %{on: true, brightness: 10}, :api, 107.0)

      assert result.published == %{on: true, brightness: 10}
      assert result.changed
      assert States.status(store, @key) == :synced
    end

    test "a matching reading changes nothing" do
      {result, _store} =
        States.apply_telemetry(commanded(%{on: true}), @key, %{on: true}, :lan, 200.0)

      refute result.changed
      refute result.needs_api_clarification
    end
  end

  test "a lamp first heard on: the LAN asks the API, the API is adopted" do
    {result, _store} = States.apply_telemetry(store(), @key, %{on: true}, :lan, 0.0)
    assert result == %{published: %{}, changed: false, needs_api_clarification: true}

    {result, store} =
      States.apply_telemetry(store(), @key, %{on: true, reachable: true}, :api, 0.0)

    assert result.changed
    assert States.published(store, @key) == %{on: true, reachable: true}
  end

  test "a lamp first heard off is adopted from the LAN" do
    {result, _store} =
      States.apply_telemetry(store(), @key, %{on: false, reachable: true}, :lan, 0.0)

    assert result == %{
             published: %{on: false, reachable: true},
             changed: true,
             needs_api_clarification: false
           }
  end

  test "lamps are kept apart" do
    {_published, store} = States.record_command(store(), "A", %{on: true}, 1.0)
    {_published, store} = States.record_command(store, "B", %{on: false}, 1.0)

    assert States.published(store, "A") == %{on: true}
    assert States.published(store, "B") == %{on: false}
  end
end
