defmodule Ziwoas.Switching.CommanderTest do
  # Mirrors test/models/switching/commander_test.rb.
  use Ziwoas.DataCase

  import Ecto.Query

  alias Ziwoas.{Config, Repo, TestClock, TestMqtt}
  alias Ziwoas.Plugs.Plug
  alias Ziwoas.Switching.{Command, Commander}

  @mqtt %Config.Mqtt{host: "localhost", port: 1883, topic_prefix: "shellies"}
  @plug %Plug{id: "lamp", name: "Lampe", role: :consumer, driver: :shelly, switchable: true}

  setup do
    TestClock.freeze("2026-06-15T18:00:00Z")
    record(:ok)
  end

  defp record(answer) do
    test = self()

    TestMqtt.record(fn client_id, topic, payload ->
      send(test, {:published, client_id, topic, payload})
      answer
    end)
  end

  defp commands, do: Repo.all(from c in Command, order_by: c.id)

  test "publishes on to the shelly command topic and logs the command" do
    assert {:ok, %Command{}} = Commander.switch(@plug, :on, :manual, @mqtt)
    assert_received {:published, "ziwoas-phoenix-command", "shellies/lamp/command/switch:0", "on"}

    assert [%Command{plug_id: "lamp", action: "on", source: "manual", inserted_at: inserted_at}] =
             commands()

    assert inserted_at == ~U[2026-06-15 18:00:00.000000Z]
  end

  test "publishes off with source schedule" do
    Commander.switch(@plug, :off, :schedule, @mqtt)
    assert_received {:published, _, "shellies/lamp/command/switch:0", "off"}
    assert [%Command{action: "off", source: "schedule"}] = commands()
  end

  test "a failed publish answers an error and writes no log row" do
    record({:error, :timeout})

    assert {:error, "MQTT publish for 'lamp' failed: :timeout"} =
             Commander.switch(@plug, :on, :manual, @mqtt)

    assert commands() == []
  end

  test "an unknown driver answers a clear error" do
    fritz = %{@plug | id: "tv", driver: :fritz_dect}
    assert {:error, message} = Commander.switch(fritz, :on, :manual, @mqtt)
    assert message =~ "fritz_dect"
    refute_received {:published, _, _, _}
    assert commands() == []
  end

  test "a plug that does not switch answers an error" do
    assert {:error, _} = Commander.switch(%{@plug | switchable: false}, :on, :manual, @mqtt)
    refute_received {:published, _, _, _}
  end

  test "an invalid action raises" do
    action = String.to_atom("toggle")
    assert_raise ArgumentError, fn -> Commander.switch(@plug, action, :manual, @mqtt) end
  end
end
