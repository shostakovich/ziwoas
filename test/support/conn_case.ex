defmodule ZiwoasWeb.ConnCase do
  @moduledoc """
  Tests that go through the endpoint: requests with `Phoenix.ConnTest`, LiveViews with
  `Phoenix.LiveViewTest`. Each test runs in the SQL sandbox like `Ziwoas.DataCase`,
  whose helpers it imports, and like it cannot run async.
  """
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
