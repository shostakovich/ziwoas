defmodule ZiwoasWeb.Plugs.RequireConfig do
  @moduledoc false
  import Plug.Conn
  import Phoenix.Controller, only: [put_view: 2, render: 3]

  alias Ziwoas.Config

  def init(opts), do: opts

  def call(conn, _opts) do
    case Config.fetch() do
      {:ok, _config} ->
        conn

      {:error, message} ->
        conn
        |> put_status(:service_unavailable)
        |> put_view(html: ZiwoasWeb.ErrorHTML)
        |> render(:config_error, message: message)
        |> halt()
    end
  end
end
