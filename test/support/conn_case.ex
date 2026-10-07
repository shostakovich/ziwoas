defmodule ZiwoasWeb.ConnCase do
  @moduledoc """
  Test case for requests against the endpoint. The Repo is read-only (the Rails
  fixture); `use ZiwoasWeb.ConnCase, db: true` gives the module a writable
  database of its own instead, like `Ziwoas.DataCase`.
  """
  use ExUnit.CaseTemplate

  using opts do
    db_setup =
      if Keyword.get(opts, :db, false) do
        quote do
          import Ziwoas.DataCase
          setup_all context, do: Ziwoas.DataCase.start_db!(context)
          setup context, do: Ziwoas.DataCase.checkout!(context)
        end
      end

    quote do
      @endpoint ZiwoasWeb.Endpoint

      use ZiwoasWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest

      unquote(db_setup)
    end
  end

  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
