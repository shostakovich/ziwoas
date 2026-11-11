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
      import ZiwoasWeb.ConnCase, only: [sign_in: 2]
    end
  end

  @doc "Signs the request in as the gate does: `X-Remote-User` from a trusted proxy."
  def sign_in(conn, name), do: Plug.Conn.put_req_header(conn, "x-remote-user", name)

  setup tags do
    Ziwoas.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
