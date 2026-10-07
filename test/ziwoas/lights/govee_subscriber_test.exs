defmodule Ziwoas.Lights.GoveeSubscriberTest do
  use Ziwoas.DataCase

  alias Ziwoas.Lights.{GoveeSubscriber, Light, State}
  alias Ziwoas.Repo

  @moduletag :capture_log

  test "subscribes to and matches config and state topics only" do
    sub = GoveeSubscriber.new()
    assert GoveeSubscriber.subscriptions(sub) == ["govees/+/config", "govees/+/state"]
    assert GoveeSubscriber.matches?(sub, "govees/14ABDB4844064B60/config")
    assert GoveeSubscriber.matches?(sub, "govees/K/state")
    refute GoveeSubscriber.matches?(sub, "govees/K/set")
    refute GoveeSubscriber.matches?(sub, "shellies/K/state")
  end

  test "configs and states become lights and their states" do
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

  test "a later config keeps the stored name and leaves an unchanged row alone" do
    stamp = ~U[2026-01-01 00:00:00.000000Z]

    Repo.insert!(%Light{
      key: "K",
      name: "Mein Name",
      sku: "H60B0",
      inserted_at: stamp,
      updated_at: stamp
    })

    GoveeSubscriber.handle(
      GoveeSubscriber.new(),
      "govees/K/config",
      ~s({"sku":"H60B0","name":"Uplighter"})
    )

    assert [%Light{name: "Mein Name", updated_at: ^stamp}] = Repo.all(Light)
  end

  test "a state message tells the lamp's page and the tile list" do
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "light_BCAST")
    Phoenix.PubSub.subscribe(Ziwoas.PubSub, "lights")

    GoveeSubscriber.handle(GoveeSubscriber.new(), "govees/BCAST/state", ~s({"on":false}))
    assert_received {:light_updated, "BCAST"}
    assert_received {:light_updated, "BCAST"}
  end

  test "a state message reaches the subscribers of all lamps and of that lamp" do
    Ziwoas.Lights.subscribe()
    Ziwoas.Lights.subscribe("BCAST")
    Ziwoas.Lights.subscribe("OTHER")

    GoveeSubscriber.handle(GoveeSubscriber.new(), "govees/BCAST/state", ~s({"on":false}))

    assert_received {:updated, "BCAST"}
    assert_received {:updated, "BCAST"}
    refute_received {:updated, _}
  end
end
