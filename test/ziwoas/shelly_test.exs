defmodule Ziwoas.ShellyTest do
  use ExUnit.Case

  alias Ziwoas.{FakeShelly, Shelly}

  test "without a connection the plug is offline" do
    assert Shelly.call("nobody", "Switch.Set", %{id: 0, on: true}) == {:error, :offline}
  end

  test "the connection answers the call" do
    FakeShelly.serve("lamp", fn method, params ->
      {:ok, %{"method" => method, "params" => params}}
    end)

    assert Shelly.call("lamp", "Switch.Set", %{on: true}) ==
             {:ok, %{"method" => "Switch.Set", "params" => %{on: true}}}
  end

  test "an answer that comes too late is a timeout and never arrives" do
    FakeShelly.serve("lamp", fn _method, _params ->
      Process.sleep(100)
      {:ok, %{}}
    end)

    assert Shelly.call("lamp", "Switch.Set", %{}, 20) == {:error, :timeout}
    refute_receive {_ref, {:ok, _result}}, 200
  end

  test "a connection that goes away while the call waits makes the plug offline" do
    FakeShelly.serve("lamp", fn _method, _params -> exit(:normal) end)

    assert Shelly.call("lamp", "Switch.Set", %{}) == {:error, :offline}
  end

  test "the newest connection takes the call" do
    FakeShelly.serve("lamp", fn _method, _params -> {:ok, :old} end)
    FakeShelly.serve("lamp", fn _method, _params -> {:ok, :new} end)

    assert Shelly.call("lamp", "Switch.Set", %{}) == {:ok, :new}
  end
end
