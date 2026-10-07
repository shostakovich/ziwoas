defmodule ZiwoasWeb.HealthController do
  @moduledoc """
  The health check on `/up`: 200 once the app has booted with a readable device
  config, a green page for HTML, `{"status":"up","timestamp":…}` for JSON (by
  Accept or `/up.json`), the timestamp ISO 8601 in the location's zone. A config
  that does not load is a 503: the app then runs no collector and no jobs.
  """
  use ZiwoasWeb, :controller

  alias Ziwoas.{Clock, Config}

  @up ~s(<!DOCTYPE html><html><body style="background-color: green"></body></html>)
  @down ~s(<!DOCTYPE html><html><body style="background-color: red"></body></html>)

  def show(conn, params) do
    case {get_format(conn), config()} do
      {"json", _} -> json_up(conn, params)
      {_, {:ok, _}} -> conn |> put_resp_content_type("text/html") |> send_resp(200, @up)
      {_, {:error, _}} -> conn |> put_resp_content_type("text/html") |> send_resp(503, @down)
    end
  end

  def json_up(conn, _params) do
    case config() do
      {:ok, config} ->
        timestamp =
          config.location.timezone
          |> Clock.now()
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()

        json(conn, %{status: "up", timestamp: timestamp})

      {:error, message} ->
        conn |> put_status(503) |> json(%{status: "down", error: message})
    end
  end

  defp config do
    {:ok, Config.app_config()}
  rescue
    error in Config.Error -> {:error, Exception.message(error)}
  end
end
