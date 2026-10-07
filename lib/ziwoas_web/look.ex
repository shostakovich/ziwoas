defmodule ZiwoasWeb.Look do
  @moduledoc """
  Carries the `look` cookie into controllers (`plug ZiwoasWeb.Look`) and
  LiveViews (`live_session ..., session: {ZiwoasWeb.Look, :session, []}`).
  """
  import Plug.Conn

  alias Ziwoas.Look

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    assign(conn, :look, Look.named(conn.cookies[Look.cookie()]))
  end

  @doc "LiveView session data: the look, read from the request's cookie."
  def session(conn) do
    conn = fetch_cookies(conn)
    %{"look" => Look.named(conn.cookies[Look.cookie()])}
  end
end
