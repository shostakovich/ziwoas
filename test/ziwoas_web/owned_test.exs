defmodule ZiwoasWeb.OwnedTest do
  use ExUnit.Case, async: true

  import Plug.Test

  defp call(task), do: ZiwoasWeb.Owned.call(conn(:post, "/x"), ZiwoasWeb.Owned.init(task: task))

  test "passes what Phoenix owns: every task" do
    refute call(:economics).halted
    refute call(:switching).halted
  end
end
