defmodule Ziwoas.Switching.Commander do
  @moduledoc """
  The single choke point for switching plugs: publishes the command over the
  command connection (`Ziwoas.Mqtt.publish/5`) and logs it to `switch_commands`
  only after the publish went out.
  """
  alias Ziwoas.{Mqtt, Repo}
  alias Ziwoas.Plugs.Plug
  alias Ziwoas.Switching.Command

  @actions [:on, :off]

  @spec switch(Plug.t(), :on | :off, :manual | :schedule, %Ziwoas.Config.Mqtt{}) ::
          {:ok, %Command{}} | {:error, String.t()}
  def switch(plug, action, source, mqtt) do
    unless action in @actions,
      do: raise(ArgumentError, "action must be one of #{inspect(@actions)}")

    with :ok <- switchable(plug),
         :ok <- publish(plug, action, mqtt) do
      command = %Command{plug_id: plug.id, action: to_string(action), source: to_string(source)}
      {:ok, Repo.insert!(command)}
    end
  end

  defp switchable(%Plug{switchable: true}), do: :ok
  defp switchable(plug), do: {:error, "plug '#{plug.id}' is not switchable"}

  defp publish(%Plug{driver: :shelly} = plug, action, mqtt) do
    topic = "#{mqtt.topic_prefix}/#{plug.id}/command/switch:0"

    case Mqtt.publish(Mqtt.command_client_id(), topic, to_string(action)) do
      :ok -> :ok
      {:error, reason} -> {:error, "MQTT publish for '#{plug.id}' failed: #{inspect(reason)}"}
    end
  end

  defp publish(plug, _action, _mqtt),
    do: {:error, "no switch driver for '#{plug.driver}' (plug '#{plug.id}')"}
end
