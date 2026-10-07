defmodule ZiwoasWeb.HealthController do
  @moduledoc false
  use ZiwoasWeb, :controller

  alias Ziwoas.Config

  def show(conn, _params) do
    case Config.fetch() do
      {:ok, _config} ->
        json(conn, %{status: "up"})

      {:error, message} ->
        conn |> put_status(:service_unavailable) |> json(%{status: "down", error: message})
    end
  end
end
