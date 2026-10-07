defmodule ZiwoasWeb.Look do
  @moduledoc false
  import Plug.Conn

  @names ~w[clean felt]
  @default "clean"
  @cookie "look"

  @spec named(term) :: String.t()
  def named(value) when value in @names, do: value
  def named(_value), do: @default

  def init(opts), do: opts

  def call(conn, _opts), do: assign(conn, :look, from_cookie(conn))

  def session(conn), do: %{"look" => from_cookie(conn)}

  defp from_cookie(conn),
    do: conn |> fetch_cookies() |> Map.fetch!(:cookies) |> Map.get(@cookie) |> named()
end
