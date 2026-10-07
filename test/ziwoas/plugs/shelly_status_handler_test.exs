defmodule Ziwoas.Plugs.ShellyStatusHandlerTest do
  # test/shelly_status_handler_test.rb beyond the replay vectors: the topics, the
  # live beat as owner, and where the rows go by mode.
  # Subscribes to a global PubSub topic another test broadcasts on.
  use Ziwoas.DataCase, async: false

  alias Ziwoas.{Ownership, Repo, TestConfigs}
  alias Ziwoas.Plugs.{Sample, ShellyStatusHandler, State}

  @moduletag :capture_log
  @now 1_700_000_000.0

  defp handler(opts \\ []),
    do: ShellyStatusHandler.new(TestConfigs.plugs(), [clock: fn -> @now end] ++ opts)

  defp payload(apower, total, extra \\ %{}),
    do: JSON.encode!(Map.merge(%{"apower" => apower, "aenergy" => %{"total" => total}}, extra))

  setup do
    on_exit(&Ownership.clear_override/0)
    :ok
  end

  test "subscribes to the switch status of every plug under the prefix" do
    assert ShellyStatusHandler.subscriptions(handler()) == ["shellies/+/status/switch:0"]
  end

  test "matches only topics under the prefix" do
    assert ShellyStatusHandler.matches?(handler(), "shellies/bkw/status/switch:0")
    refute ShellyStatusHandler.matches?(handler(), "govee/lamp/status")
    refute ShellyStatusHandler.matches?(handler(), "shellies-other/bkw/status/switch:0")
  end

  test "as owner the deltas go out on the dashboard topic", %{repo: repo} do
    Repo.put_writer(:main, repo)
    Ownership.override(%{plug_ingest: :phoenix})
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "dashboard")

    ShellyStatusHandler.handle(
      handler(),
      "shellies/bkw/status/switch:0",
      payload(-300.0, 1234.5)
    )

    assert_receive {:dashboard_live, [delta]}

    assert delta == [
             {"id", "bkw"},
             {"name", "BKW"},
             {"role", :producer},
             {"apower_w", -300.0},
             {"last_seen_ts", 1_700_000_000},
             {"bucket_ts", 1_699_999_980},
             {"avg_power_w", 300.0},
             {"output", nil}
           ]
  end

  test "in shadow mode rows go to the shadow database and nothing is broadcast", %{repo: repo} do
    Repo.put_writer(:main, :no_main_writer)
    Repo.put_writer(:shadow, repo)
    Ownership.override(%{plug_ingest: :shadow})
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "dashboard")

    ShellyStatusHandler.handle(
      handler(),
      "shellies/fridge/status/switch:0",
      payload(50.0, 1.0, %{"output" => true})
    )

    assert [%Sample{plug_id: "fridge", ts: 1_700_000_000, apower_w: 50.0}] = Repo.all(Sample)
    assert [%State{plug_id: "fridge", output: true}] = Repo.all(State)
    refute_receive {:dashboard_live, _}
  end

  test "an output that stays the same is not written again", %{repo: repo} do
    Repo.put_writer(:main, repo)
    Ownership.override(%{plug_ingest: :phoenix})

    Repo.insert!(%State{
      plug_id: "fridge",
      output: true,
      updated_at: ~U[2026-01-01 00:00:00.000000Z]
    })

    ShellyStatusHandler.handle(
      handler(),
      "shellies/fridge/status/switch:0",
      payload(50.0, 1.0, %{"output" => "on"})
    )

    assert [%State{output: true, updated_at: ~U[2026-01-01 00:00:00.000000Z]}] = Repo.all(State)
  end

  test "output casts like ActiveRecord's boolean column" do
    assert State.cast_output(nil) == nil
    assert State.cast_output("") == nil

    for falsy <- [false, 0, 0.0, "0", "f", "F", "false", "FALSE", "off", "OFF"],
        do: refute(State.cast_output(falsy))

    for truthy <- [true, 1, "1", "on", "yes", "False", "x", [], %{}],
        do: assert(State.cast_output(truthy))
  end
end
