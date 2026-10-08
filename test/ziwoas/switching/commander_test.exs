defmodule Ziwoas.Switching.CommanderTest do
  use Ziwoas.DataCase

  import Ecto.Query

  alias Ziwoas.{FakeShelly, Repo, TestClock}
  alias Ziwoas.Plugs.{Plug, State}
  alias Ziwoas.Switching.{Command, Commander}

  @plug %Plug{id: "lamp", name: "Lampe", role: :consumer, driver: :shelly, switchable: true}

  setup do
    TestClock.freeze("2026-06-15T18:00:00Z")
    :ok
  end

  defp commands, do: Repo.all(from c in Command, order_by: c.id)

  test "sends Switch.Set on to the plug's Shelly and logs the command" do
    FakeShelly.serve("lamp")

    assert {:ok, %Command{}} = Commander.switch(@plug, :on, :manual)
    assert_received {:shelly_rpc, "lamp", "Switch.Set", %{id: 0, on: true}}

    assert [%Command{plug_id: "lamp", action: :on, source: :manual, inserted_at: inserted_at}] =
             commands()

    assert inserted_at == ~U[2026-06-15 18:00:00.000000Z]
  end

  test "sends off with source schedule" do
    FakeShelly.serve("lamp")

    Commander.switch(@plug, :off, :schedule)
    assert_received {:shelly_rpc, "lamp", "Switch.Set", %{id: 0, on: false}}
    assert [%Command{action: :off, source: :schedule}] = commands()
  end

  test "the relay state is left to the plug's connection" do
    FakeShelly.serve("lamp")

    assert {:ok, %Command{}} = Commander.switch(@plug, :on, :manual)
    assert Repo.all(State) == []
  end

  test "a plug without a connection answers an error and writes nothing" do
    assert {:error, {:unreachable, :offline}} = Commander.switch(@plug, :on, :manual)
    assert commands() == []
    assert Repo.all(State) == []
  end

  test "an error answer from the Shelly is a rejection and writes no log row" do
    FakeShelly.serve("lamp", fn _method, _params -> {:error, {:rpc, -103, "busy"}} end)

    assert {:error, {:rejected, {-103, "busy"}}} = Commander.switch(@plug, :on, :manual)
    assert commands() == []
  end

  test "an unknown driver answers a clear error" do
    fritz = %{@plug | id: "tv", driver: :fritz_dect}
    assert {:error, {:no_driver, :fritz_dect}} = Commander.switch(fritz, :on, :manual)
    assert commands() == []
  end

  test "a plug that does not switch answers an error" do
    assert {:error, :not_switchable} =
             Commander.switch(%{@plug | switchable: false}, :on, :manual)
  end

  test "an action outside the enum does not match" do
    action = String.to_atom("toggle")
    assert_raise FunctionClauseError, fn -> Commander.switch(@plug, action, :manual) end
    assert commands() == []
  end
end
