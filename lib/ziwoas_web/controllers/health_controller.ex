defmodule ZiwoasWeb.HealthController do
  @moduledoc """
  `GET /up` for the container health check: `{"status":"up"}`, or a 503 with
  the error when the device config did not load at boot.
  """
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
