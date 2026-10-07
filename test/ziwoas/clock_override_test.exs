defmodule Ziwoas.ClockOverrideTest do
  # Flips application env: runs with the synchronous modules, after the async ones.
  use ExUnit.Case, async: false

  alias Ziwoas.Clock

  setup do
    on_exit(fn ->
      Application.put_env(:ziwoas, :clock_process_override, true)
      Clock.unfreeze()
    end)
  end

  test "outside test support a process override is ignored" do
    Application.put_env(:ziwoas, :clock_process_override, false)
    Clock.freeze("2020-01-01T00:00:00Z")
    assert Clock.now().year >= 2026
  end
end
