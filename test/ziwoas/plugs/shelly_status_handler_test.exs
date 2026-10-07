defmodule Ziwoas.Plugs.ShellyStatusHandlerTest do
  # Subscribes to a global PubSub topic another test broadcasts on.
  use Ziwoas.DataCase

  import ExUnit.CaptureLog

  alias Ziwoas.Plugs.{Sample, ShellyStatusHandler, State}
  alias Ziwoas.{Repo, TestConfigs}

  @moduletag :capture_log
  @now 1_700_000_000.0
  @fridge "shellies/fridge/status/switch:0"

  defp handler(opts \\ []) do
    test = self()

    ShellyStatusHandler.new(
      TestConfigs.plugs(),
      Keyword.merge([clock: fn -> @now end, broadcast: &send(test, {:broadcast, &1})], opts)
    )
  end

  defp payload(apower, total, extra \\ %{}),
    do: JSON.encode!(Map.merge(%{"apower" => apower, "aenergy" => %{"total" => total}}, extra))

  test "subscribes to the switch status of every plug under the prefix" do
    assert ShellyStatusHandler.subscriptions(handler()) == ["shellies/+/status/switch:0"]
  end

  test "matches only topics under the prefix" do
    assert ShellyStatusHandler.matches?(handler(), "shellies/bkw/status/switch:0")
    refute ShellyStatusHandler.matches?(handler(), "govee/lamp/status")
    refute ShellyStatusHandler.matches?(handler(), "shellies-other/bkw/status/switch:0")
  end

  test "by default the deltas go out on the dashboard topic" do
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "dashboard")
    handler = ShellyStatusHandler.new(TestConfigs.plugs(), clock: fn -> @now end)

    ShellyStatusHandler.handle(handler, "shellies/bkw/status/switch:0", payload(-300.0, 1234.5))

    assert_receive {:dashboard_live, [delta]}

    assert delta == %{
             id: "bkw",
             name: "BKW",
             role: :producer,
             apower_w: -300.0,
             last_seen_ts: 1_700_000_000,
             bucket_ts: 1_699_999_980,
             avg_power_w: 300.0,
             output: nil
           }
  end

  test "a report becomes a sample and the plug's output" do
    ShellyStatusHandler.handle(handler(), @fridge, payload(50, 1, %{"output" => true}))

    assert [%Sample{plug_id: "fridge", ts: 1_700_000_000, apower_w: 50.0, aenergy_wh: 1.0}] =
             Repo.all(Sample)

    assert [%State{plug_id: "fridge", output: true}] = Repo.all(State)
  end

  test "an output that stays the same is not written again" do
    Repo.insert!(%State{
      plug_id: "fridge",
      output: true,
      updated_at: ~U[2026-01-01 00:00:00.000000Z]
    })

    ShellyStatusHandler.handle(handler(), @fridge, payload(50.0, 1.0, %{"output" => true}))

    assert [%State{output: true, updated_at: ~U[2026-01-01 00:00:00.000000Z]}] = Repo.all(State)
  end

  test "an output that changes is updated" do
    Repo.insert!(%State{plug_id: "fridge", output: true})

    ShellyStatusHandler.handle(handler(), @fridge, payload(0.0, 1.0, %{"output" => false}))

    assert [%State{output: false}] = Repo.all(State)
  end

  test "an output that is not a boolean keeps the sample but says nothing about the relay" do
    ShellyStatusHandler.handle(handler(), @fridge, payload(50.0, 1.0, %{"output" => "on"}))

    assert [%Sample{plug_id: "fridge"}] = Repo.all(Sample)
    assert Repo.all(State) == []
    assert_received {:broadcast, [%{id: "fridge", output: nil}]}
  end

  test "a second report in the same second is a duplicate and changes nothing" do
    first = ShellyStatusHandler.handle(handler(), @fridge, payload(50.0, 1.0))
    assert_received {:broadcast, _}

    assert ShellyStatusHandler.handle(first, @fridge, payload(70.0, 2.0)) == first
    assert [%Sample{apower_w: 50.0}] = Repo.all(Sample)
  end

  describe "the live deltas" do
    test "collect per plug and go out at most every 5 s, a plug keeping its place" do
      clock = :counters.new(1, [])
      :counters.put(clock, 1, 1_700_000_000)
      handler = handler(clock: fn -> :counters.get(clock, 1) * 1.0 end)

      tick = fn state, seconds, topic, watts ->
        :counters.add(clock, 1, seconds)
        ShellyStatusHandler.handle(state, topic, payload(watts, 1.0))
      end

      state = tick.(handler, 0, @fridge, 100.0)
      assert_received {:broadcast, [%{id: "fridge", avg_power_w: 100.0}]}

      state = tick.(state, 1, "shellies/bkw/status/switch:0", -400.0)
      state = tick.(state, 1, @fridge, 200.0)
      refute_received {:broadcast, _}

      _state = tick.(state, 3, "shellies/bkw/status/switch:0", -600.0)
      assert_received {:broadcast, [bkw, fridge]}

      assert {bkw.id, bkw.apower_w, bkw.avg_power_w} == {"bkw", -600.0, 500.0}
      assert {fridge.id, fridge.apower_w, fridge.avg_power_w} == {"fridge", 200.0, 150.0}
    end

    test "a new minute starts a new mean" do
      clock = :counters.new(1, [])
      :counters.put(clock, 1, 1_700_000_039)
      handler = handler(clock: fn -> :counters.get(clock, 1) * 1.0 end)

      state = ShellyStatusHandler.handle(handler, @fridge, payload(100.0, 1.0))
      assert_received {:broadcast, [%{bucket_ts: 1_699_999_980}]}

      :counters.add(clock, 1, 10)
      ShellyStatusHandler.handle(state, @fridge, payload(300.0, 1.0))

      assert_received {:broadcast, [%{bucket_ts: 1_700_000_040, avg_power_w: 300.0}]}
    end
  end

  describe "error paths leave the state as it was and write nothing" do
    test "broken JSON" do
      state = handler()

      log =
        capture_log(fn ->
          assert ShellyStatusHandler.handle(state, @fridge, ~s({"apower": 5,)) == state
        end)

      assert log =~ "invalid JSON on #{@fridge}"
      assert Repo.all(Sample) == []
    end

    test "JSON that is not an object" do
      state = handler()

      for payload <- ["[1, 2]", "42", ~s("on"), "null"] do
        assert ShellyStatusHandler.handle(state, @fridge, payload) == state
      end

      assert Repo.all(Sample) == []
    end

    test "missing or non-numeric fields" do
      state = handler()

      payloads = [
        JSON.encode!(%{"aenergy" => %{"total" => 1.0}}),
        JSON.encode!(%{"apower" => 5.0}),
        JSON.encode!(%{"apower" => 5.0, "aenergy" => 12.0}),
        JSON.encode!(%{"apower" => 5.0, "aenergy" => %{}}),
        payload("5", 1.0),
        payload(5.0, nil)
      ]

      for payload <- payloads do
        log =
          capture_log(fn ->
            assert ShellyStatusHandler.handle(state, @fridge, payload) == state
          end)

        assert log =~ "status without apower or aenergy.total"
      end

      assert Repo.all(Sample) == []
      refute_received {:broadcast, _}
    end

    test "an unknown plug" do
      state = handler()
      topic = "shellies/toaster/status/switch:0"

      log =
        capture_log(fn ->
          assert ShellyStatusHandler.handle(state, topic, payload(5.0, 1.0)) == state
        end)

      assert log =~ "unknown plug 'toaster'"
      assert Repo.all(Sample) == []
    end

    test "a topic too short to name a plug" do
      state = handler()
      assert ShellyStatusHandler.handle(state, "shellies", payload(5.0, 1.0)) == state
      assert Repo.all(Sample) == []
    end
  end
end
