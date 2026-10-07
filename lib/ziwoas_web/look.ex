defmodule ZiwoasWeb.Look do
  @moduledoc """
  The page look: plain felt-css (`"clean"`, the default) or the felt texture
  (`"felt"`), kept in the unsigned `look` cookie.

  The header's toggle switches it in the browser (`assets/js/lib/look.js` sets
  `data-look`, the cookie and the browser chrome's colour) and tells the
  LiveView with `"set_look"` (`ZiwoasWeb.Nav`). The server only reads the
  cookie, so a full page load renders in the chosen look without a flash:
  `plug ZiwoasWeb.Look` for controllers, `session/1` for the `live_session`.
  """
  import Plug.Conn

  @names ~w[clean felt]
  @default "clean"
  @cookie "look"

  @doc "The look a value names; anything else is the default."
  @spec named(term) :: String.t()
  def named(value) when value in @names, do: value
  def named(_value), do: @default

  def init(opts), do: opts

  def call(conn, _opts), do: assign(conn, :look, from_cookie(conn))

  @doc "LiveView session data: the look, read from the request's cookie."
  def session(conn), do: %{"look" => from_cookie(conn)}

  defp from_cookie(conn),
    do: conn |> fetch_cookies() |> Map.fetch!(:cookies) |> Map.get(@cookie) |> named()
end
