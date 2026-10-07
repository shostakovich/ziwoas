defmodule Ziwoas.Plugs.IngestTest do
  # Subscribes to a global PubSub topic another test broadcasts on.
  use Ziwoas.DataCase

  alias Ziwoas.{Config, Repo, TestConfigs}
  alias Ziwoas.Plugs.{Ingest, Roster, Sample, State}

  @now 1_700_000_000.0

  defp plug(id), do: TestConfigs.plugs() |> Config.plug_roster() |> Roster.find(id)

  defp ingest(opts \\ []) do
    test = self()

    Ingest.new(
      Keyword.merge([clock: fn -> @now end, broadcast: &send(test, {:broadcast, &1})], opts)
    )
  end

  defp reading(apower, total, output \\ nil),
    do: %{apower_w: apower * 1.0, aenergy_wh: total * 1.0, output: output}

  test "by default the deltas go to Plugs' subscribers" do
    Ziwoas.Plugs.subscribe()

    Ingest.record(Ingest.new(clock: fn -> @now end), plug("bkw"), reading(-300, 1234.5))

    assert_receive {:live, [delta]}

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

  test "a reading becomes a sample and the plug's output" do
    Ingest.record(ingest(), plug("fridge"), reading(50, 1, true))

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

    Ingest.record(ingest(), plug("fridge"), reading(50, 1, true))

    assert [%State{output: true, updated_at: ~U[2026-01-01 00:00:00.000000Z]}] = Repo.all(State)
  end

  test "a reading without an output says nothing about the relay" do
    Ingest.record(ingest(), plug("fridge"), reading(50, 1))

    assert [%Sample{}] = Repo.all(Sample)
    assert Repo.all(State) == []
  end

  test "a second reading in the same second keeps the sample, but updates the relay" do
    first = Ingest.record(ingest(), plug("fridge"), reading(50, 1, true))
    assert_received {:broadcast, _}

    second = Ingest.record(first, plug("fridge"), reading(70, 2, false))
    assert [%Sample{apower_w: 50.0}] = Repo.all(Sample)
    assert [%State{output: false}] = Repo.all(State)

    Ingest.flush(second)
    assert_received {:broadcast, [%{apower_w: 50.0, output: false}]}
  end

  test "a relay output alone goes out with the plug's last watts, once per change" do
    state = Ingest.record(ingest(), plug("fridge"), reading(50, 1, true))
    assert_received {:broadcast, _}

    state = Ingest.record_output(state, plug("fridge"), false)
    assert [%State{output: false}] = Repo.all(State)

    state = state |> Ingest.flush() |> Ingest.record_output(plug("fridge"), false)
    assert_received {:broadcast, [%{apower_w: 50.0, avg_power_w: 50.0, output: false}]}
    refute Ingest.pending?(state)
  end

  test "a relay output before any reading is stored, but has no delta to go out with" do
    state = Ingest.record_output(ingest(), plug("fridge"), true)

    assert [%State{output: true}] = Repo.all(State)
    refute Ingest.pending?(state)
  end

  describe "the live deltas" do
    test "collect per plug and go out at most every 5 s, a plug keeping its place" do
      clock = :counters.new(1, [])
      :counters.put(clock, 1, 1_700_000_000)
      ingest = ingest(clock: fn -> :counters.get(clock, 1) * 1.0 end)

      tick = fn state, seconds, id, watts ->
        :counters.add(clock, 1, seconds)
        Ingest.record(state, plug(id), reading(watts, 1))
      end

      state = tick.(ingest, 0, "fridge", 100)
      assert_received {:broadcast, [%{id: "fridge", avg_power_w: 100.0}]}

      state = tick.(state, 1, "bkw", -400)
      state = tick.(state, 1, "fridge", 200)
      refute_received {:broadcast, _}
      assert Ingest.pending?(state)

      state = tick.(state, 3, "bkw", -600)
      assert_received {:broadcast, [bkw, fridge]}
      refute Ingest.pending?(state)

      assert {bkw.id, bkw.apower_w, bkw.avg_power_w} == {"bkw", -600.0, 500.0}
      assert {fridge.id, fridge.apower_w, fridge.avg_power_w} == {"fridge", 200.0, 150.0}
    end

    test "flush sends the waiting deltas at once, and nothing when none wait" do
      clock = :counters.new(1, [])
      :counters.put(clock, 1, 1_700_000_000)
      ingest = ingest(clock: fn -> :counters.get(clock, 1) * 1.0 end)

      state = Ingest.record(ingest, plug("fridge"), reading(100, 1))
      assert_received {:broadcast, _}

      :counters.add(clock, 1, 1)
      state = Ingest.record(state, plug("fridge"), reading(0, 1, false))
      refute_received {:broadcast, _}

      state = Ingest.flush(state)
      assert_received {:broadcast, [%{id: "fridge", output: false}]}

      assert Ingest.flush(state) == state
      refute_received {:broadcast, _}
    end
  end
end
