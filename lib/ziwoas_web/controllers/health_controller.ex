defmodule ZiwoasWeb.HealthController do
  @moduledoc """
  The health check on `/up`: 200 once the app has booted, a green page for
  HTML, `{"status":"up","timestamp":…}` for JSON (by Accept or `/up.json`),
  the timestamp ISO 8601 in the location's zone.
  """
  use ZiwoasWeb, :controller

  alias Ziwoas.{Clock, Config}

  @page ~s(<!DOCTYPE html><html><body style="background-color: green"></body></html>)

  def show(conn, _params) do
    case get_format(conn) do
      "json" -> json_up(conn, %{})
      _ -> conn |> put_resp_content_type("text/html") |> send_resp(200, @page)
    end
  end

  def json_up(conn, _params) do
    timestamp =
      Config.app_config().location.timezone
      |> Clock.now()
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    json(conn, %{status: "up", timestamp: timestamp})
  end
end
