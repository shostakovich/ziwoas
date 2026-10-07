defmodule ZiwoasWeb.PlugSwitchController do
  @moduledoc """
  The plug button (Rails' `PlugSwitchesController`): `POST /plugs/:plug_id/switch?state=on|off`
  switches by hand and streams the plug's head back, or the broker error into it.
  """
  use ZiwoasWeb, :controller

  alias Ziwoas.{Clock, Config}
  alias Ziwoas.Switching.{Commander, Row}
  alias ZiwoasWeb.{SwitchesComponents, TurboStream}

  plug ZiwoasWeb.Owned, task: :switching

  @failed "Schalten fehlgeschlagen — MQTT-Broker nicht erreichbar"

  def failed_message, do: @failed

  def create(conn, params) do
    config = Config.app_config()

    case Enum.find(config.plugs, &(&1.id == params["plug_id"])) do
      nil ->
        TurboStream.head(conn, :not_found)

      plug ->
        if plug.switchable and params["state"] in ~w[on off],
          do: switch(conn, config, plug, String.to_existing_atom(params["state"])),
          else: TurboStream.head(conn, :unprocessable_entity)
    end
  end

  defp switch(conn, config, plug, action) do
    case Commander.switch(plug, action, :manual, config.mqtt) do
      {:ok, _command} ->
        zone = config.location.timezone
        row = Row.build(plug, Clock.now(), zone)

        TurboStream.send(conn, [
          {"replace", "sw_head_#{plug.id}",
           TurboStream.component(&SwitchesComponents.head/1, %{row: row, zone: zone})}
        ])

      {:error, _message} ->
        TurboStream.send(conn, [{"update", "sw_error_#{plug.id}", @failed}], 503)
    end
  end
end
