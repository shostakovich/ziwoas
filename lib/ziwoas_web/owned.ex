defmodule ZiwoasWeb.Owned do
  @moduledoc """
  Guards a route that writes or switches: answers 421 Misdirected Request unless
  Phoenix owns the task (`Ziwoas.Ownership.owner?/1`), as Rails' `owned_by` does
  for the tasks Phoenix owns. The reverse proxy should not send it here then. An
  owned task whose lease Rails holds (`Ziwoas.Lease`) answers 503, as Rails does.

      plug ZiwoasWeb.Owned, task: :economics
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: Keyword.fetch!(opts, :task)

  @impl true
  def call(conn, task) do
    cond do
      not Ziwoas.Ownership.owner?(task) -> conn |> send_resp(:misdirected_request, "") |> halt()
      not Ziwoas.Lease.held?(task) -> conn |> send_resp(:service_unavailable, "") |> halt()
      true -> conn
    end
  end
end
