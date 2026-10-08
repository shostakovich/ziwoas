defmodule ZiwoasWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using opts do
    Ziwoas.DataCase.check_sync!(__CALLER__.module, opts)

    quote do
      @endpoint ZiwoasWeb.Endpoint

      use ZiwoasWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Ziwoas.DataCase
    end
  end

  setup tags do
    Ziwoas.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
