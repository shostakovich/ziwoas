defmodule ZiwoasWeb.OwnedTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Ziwoas.Ownership

  setup do: on_exit(&Ownership.clear_override/0)

  defp call(task), do: ZiwoasWeb.Owned.call(conn(:post, "/x"), ZiwoasWeb.Owned.init(task: task))

  test "passes only what Phoenix owns" do
    Ownership.override(%{economics: :phoenix, switching: :dry_run})

    refute call(:economics).halted
    assert %{halted: true, status: 421} = call(:switching)
    assert %{halted: true, status: 421} = call(:light_settings)
  end
end
