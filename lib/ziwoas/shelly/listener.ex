defmodule Ziwoas.Shelly.Listener do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  alias Ziwoas.Plugs.Roster
  alias Ziwoas.Shelly.Connection

  # The connection pings every 30 s; a device whose pong stays away is gone.
  @idle_timeout_ms 75_000

  @impl true
  def init(opts), do: Keyword.fetch!(opts, :roster)

  @impl true
  def call(%Plug.Conn{method: "GET", path_info: ["shelly", plug_id]} = conn, roster) do
    with %{driver: :shelly} = plug <- Roster.find(roster, plug_id),
         :ok <- WebSockAdapter.UpgradeValidation.validate_upgrade(conn) do
      conn
      |> WebSockAdapter.upgrade(Connection, %{plug: plug, peer: peer(conn)},
        timeout: @idle_timeout_ms
      )
      |> halt()
    else
      {:error, reason} -> conn |> send_resp(400, reason) |> halt()
      _not_a_shelly -> not_found(conn)
    end
  end

  def call(conn, _roster), do: not_found(conn)

  defp not_found(conn), do: conn |> send_resp(404, "") |> halt()

  defp peer(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
