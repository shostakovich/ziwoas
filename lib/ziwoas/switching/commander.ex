defmodule Ziwoas.Switching.Commander do
  @moduledoc """
  The single choke point for switching plugs: publishes the command over the
  command connection (`Ziwoas.Mqtt.publish/4`) and logs it to `switch_commands`
  only after the publish went out.
  """
  alias Ziwoas.{Mqtt, Repo}
  alias Ziwoas.Plugs.Plug
  alias Ziwoas.Switching.Command

  @type error :: :not_switchable | {:no_driver, atom} | {:publish, term}

  @spec switch(Plug.t(), Command.action(), Command.source(), Ziwoas.Config.Mqtt.t()) ::
          {:ok, Command.t()} | {:error, error}
  def switch(plug, action, source, mqtt)
      when action in [:on, :off] and source in [:manual, :schedule] do
    with :ok <- switchable(plug),
         :ok <- publish(plug, action, mqtt) do
      {:ok, Repo.insert!(%Command{plug_id: plug.id, action: action, source: source})}
    end
  end

  defp switchable(%Plug{switchable: true}), do: :ok
  defp switchable(_plug), do: {:error, :not_switchable}

  defp publish(%Plug{driver: :shelly} = plug, action, mqtt) do
    topic = "#{mqtt.topic_prefix}/#{plug.id}/command/switch:0"

    case Mqtt.publish(Mqtt.command_client_id(), topic, Atom.to_string(action)) do
      :ok -> :ok
      {:error, reason} -> {:error, {:publish, reason}}
    end
  end

  defp publish(plug, _action, _mqtt), do: {:error, {:no_driver, plug.driver}}
end
