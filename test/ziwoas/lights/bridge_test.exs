defmodule Ziwoas.Lights.BridgeTest do
  use ExUnit.Case, async: false

  import Ziwoas.HueFixtures

  alias Ziwoas.{FakeGoveeBridge, HueStub}
  alias Ziwoas.Lights.{Bridge, Light}

  @light %Light{key: "FL1", vendor: :govee}

  describe "a Govee lamp" do
    setup do
      start_supervised!({FakeGoveeBridge, test: self(), silent: ["FL1"]})
      :ok
    end

    test "gets its commands through the Govee bridge" do
      assert Bridge.command(@light, {:brightness, 40}) == :ok
      assert_received {:govee, "FL1", {:brightness, 40}}
    end

    test "is silent as the Govee bridge has it" do
      assert Bridge.silent?(@light)
      refute Bridge.silent?(%{@light | key: "FL2"})
    end

    test "is watched for by the caller until unwatched" do
      assert Bridge.watch(@light) == :ok
      assert_received {:govee_watch, "FL1"}

      FakeGoveeBridge.hear("FL1", %{on: true})
      assert_receive {:lamp_heard, "FL1", %{on: true}}

      assert Bridge.unwatch(@light) == :ok
      assert_received {:govee_unwatch, "FL1"}
    end
  end

  describe "a Hue lamp" do
    setup do
      HueStub.start_bridge!(
        put_lamp: fn _lamp -> {:ok, nil} end,
        put_state: fn _key, state -> {:ok, state} end,
        stored_keys: fn -> [] end
      )

      :ok
    end

    test "gets its commands through the Hue bridge" do
      assert Bridge.command(hue(candle()), {:power, true}) == :ok

      candle = candle()
      assert_received {:hue_put, ^candle, %{"on" => %{"on" => true}}}
    end

    test "is silent as the Hue bridge has it, and watched through it" do
      assert Bridge.silent?(hue(colour_only()))
      refute Bridge.silent?(hue(candle()))
      assert Bridge.watch(hue(candle())) == :ok
    end
  end

  defp hue(id), do: %Light{key: key(id), vendor: :hue}

  test "without a running bridge a lamp is unavailable and never silent" do
    assert Bridge.command(@light, {:power, true}) == {:error, :unavailable}
    refute Bridge.silent?(@light)
    assert Bridge.watch(@light) == {:error, :unavailable}
    assert Bridge.unwatch(@light) == :ok
  end
end
