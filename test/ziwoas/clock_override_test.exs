defmodule Ziwoas.ClockOverrideTest do
  # Flips application env: runs with the synchronous modules, after the async ones.
  use ExUnit.Case, async: false

  alias Ziwoas.{Clock, TestClock}

  setup do
    frozen_clock = Application.fetch_env!(:ziwoas, :frozen_clock)

    on_exit(fn ->
      Application.put_env(:ziwoas, :frozen_clock, frozen_clock)
      TestClock.unfreeze()
    end)
  end

  test "without the test config a frozen instant is ignored" do
    Application.delete_env(:ziwoas, :frozen_clock)
    TestClock.freeze("2020-01-01T00:00:00Z")
    assert Clock.now().year >= 2026
  end
end
