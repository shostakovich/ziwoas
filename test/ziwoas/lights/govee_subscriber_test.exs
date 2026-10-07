defmodule Ziwoas.Lights.GoveeSubscriberTest do
  # test/govees/subscriber_test.rb beyond the replay vectors.
  use Ziwoas.DataCase, async: true

  alias Ziwoas.{Ownership, Repo}
  alias Ziwoas.Lights.{GoveeSubscriber, Light, State}

  @moduletag :capture_log

  setup do
    on_exit(&Ownership.clear_override/0)
    :ok
  end

  test "subscribes to and matches config and state topics only" do
    sub = GoveeSubscriber.new()
    assert GoveeSubscriber.subscriptions(sub) == ["govees/+/config", "govees/+/state"]
    assert GoveeSubscriber.matches?(sub, "govees/14ABDB4844064B60/config")
    assert GoveeSubscriber.matches?(sub, "govees/K/state")
    refute GoveeSubscriber.matches?(sub, "govees/K/set")
    refute GoveeSubscriber.matches?(sub, "shellies/K/state")
  end

  test "in shadow mode lights and states go to the shadow database", %{repo: repo} do
    Repo.put_writer(:main, :no_main_writer)
    Repo.put_writer(:shadow, repo)
    Ownership.override(%{light_ingest: :shadow})
    sub = GoveeSubscriber.new()

    GoveeSubscriber.handle(
      sub,
      "govees/K/config",
      ~s({"sku":"H60B0","name":"Uplighter","zones":["rippleLightToggle"]})
    )

    GoveeSubscriber.handle(
      sub,
      "govees/K/state",
      ~s({"on":true,"brightness":55,"zone_states":{"rippleLightToggle":true}})
    )

    assert [
             %Light{
               key: "K",
               name: "Uplighter",
               zones: ["rippleLightToggle"],
               firmware_scenes: nil
             }
           ] = Repo.all(Light)

    assert [
             %State{
               light_key: "K",
               on: true,
               brightness: 55,
               zone_states: %{"rippleLightToggle" => true}
             }
           ] =
             Repo.all(State)
  end

  test "a later config keeps the stored name and leaves an unchanged row alone", %{repo: repo} do
    Repo.put_writer(:main, repo)
    Ownership.override(%{light_ingest: :phoenix})
    stamp = ~U[2026-01-01 00:00:00.000000Z]

    Repo.insert!(%Light{
      key: "K",
      name: "Mein Name",
      sku: "H60B0",
      created_at: stamp,
      updated_at: stamp
    })

    GoveeSubscriber.handle(
      GoveeSubscriber.new(),
      "govees/K/config",
      ~s({"sku":"H60B0","name":"Uplighter"})
    )

    assert [%Light{name: "Mein Name", updated_at: ^stamp}] = Repo.all(Light)
  end

  test "a state message tells the lamp's page and the tile list, only as owner", %{repo: repo} do
    Repo.put_writer(:main, repo)
    Repo.put_writer(:shadow, repo)
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "light_BCAST")
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "lights")

    Ownership.override(%{light_ingest: :shadow})
    GoveeSubscriber.handle(GoveeSubscriber.new(), "govees/BCAST/state", ~s({"on":true}))
    refute_received {:light_updated, "BCAST"}

    Ownership.override(%{light_ingest: :phoenix})
    GoveeSubscriber.handle(GoveeSubscriber.new(), "govees/BCAST/state", ~s({"on":false}))
    assert_received {:light_updated, "BCAST"}
    assert_received {:light_updated, "BCAST"}
  end
end
