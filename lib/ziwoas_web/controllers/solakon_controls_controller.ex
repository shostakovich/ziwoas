defmodule ZiwoasWeb.SolakonControlsController do
  @moduledoc """
  Rails' `SolakonControlsController`: `PATCH /solakon/eps` switches the outdoor
  socket, `PATCH /solakon/control` pauses or resumes the Auto-Regelung, both
  answering JSON as Rails does. Phoenix's own PV page switches through LiveView
  events instead (`ZiwoasWeb.SolakonLive`); these routes serve whatever still
  PATCHes them, Rails' Stimulus controller included.
  """
  use ZiwoasWeb, :controller

  require Logger

  alias Ziwoas.{Config, RubyJSON}
  alias Ziwoas.Solakon.Control
  alias Ziwoas.Solakon.Control.State

  plug ZiwoasWeb.Owned, task: :solakon_control

  def eps(conn, params) do
    if is_nil(Config.app_config().solakon) do
      json(conn, 503, [{"error", "Solakon nicht konfiguriert"}])
    else
      enabled = cast_boolean(params["enabled"])

      case Control.set_eps_output(enabled) do
        {:ok, enabled} ->
          json(conn, 200, [{"enabled", enabled}])

        {:error, reason} ->
          Logger.warning("solakon_controls: EPS switch failed: #{inspect(reason)}")
          json(conn, 503, [{"error", "Schalten fehlgeschlagen"}])
      end
    end
  end

  def control(conn, params) do
    case Control.set_active(Config.app_config(), cast_boolean(params["active"])) do
      {:ok, state} -> json(conn, 200, [{"active", State.active?(state)}])
      {:error, :not_configured} -> json(conn, 503, [{"error", "Solakon nicht konfiguriert"}])
      {:error, :disabled} -> json(conn, 403, [{"error", "in Konfiguration deaktiviert"}])
    end
  end

  @false_values [false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"]

  @doc "`ActiveModel::Type::Boolean.new.cast`, JSON's true and false included."
  def cast_boolean(value) when value in [nil, ""], do: nil
  def cast_boolean(value) when value in @false_values, do: false
  def cast_boolean(_value), do: true

  defp json(conn, status, pairs) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, RubyJSON.encode!(pairs))
  end
end
