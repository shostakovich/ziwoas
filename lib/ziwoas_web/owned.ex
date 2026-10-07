defmodule ZiwoasWeb.Owned do
  @moduledoc """
  Guards a route that writes or switches: answers 421 Misdirected Request unless
  Phoenix owns the task (`Ziwoas.Ownership.owner?/1`), as Rails' `owned_by` does
  for the tasks Phoenix owns. The reverse proxy should not send it here then.

      plug ZiwoasWeb.Owned, task: :economics
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: Keyword.fetch!(opts, :task)

  @impl true
  def call(conn, task) do
    if Ziwoas.Ownership.owner?(task),
      do: conn,
      else: conn |> send_resp(:misdirected_request, "") |> halt()
  end
end
