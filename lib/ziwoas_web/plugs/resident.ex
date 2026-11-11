defmodule ZiwoasWeb.Plugs.Resident do
  @moduledoc """
  Keeps the signed-in resident in the session (ADR-0016): the name in `X-Remote-User`, set by
  the gate, counts only from a trusted proxy. Any other request is anonymous.
  """
  @behaviour Plug

  import Plug.Conn

  alias ZiwoasWeb.TrustedProxies

  @max_length 64

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case {resident(conn), get_session(conn, :resident)} do
      {same, same} -> conn
      {nil, _stale} -> delete_session(conn, :resident)
      {name, _other} -> put_session(conn, :resident, name)
    end
  end

  @spec resident(Plug.Conn.t()) :: String.t() | nil
  defp resident(conn) do
    with true <- TrustedProxies.trusted?(conn.remote_ip),
         [value] <- get_req_header(conn, "x-remote-user"),
         name when name != "" <- String.trim(value),
         true <- String.valid?(name) and String.length(name) <= @max_length do
      name
    else
      _anonymous -> nil
    end
  end
end
