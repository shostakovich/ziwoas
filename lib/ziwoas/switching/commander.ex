defmodule Ziwoas.Switching.Commander do
  @moduledoc """
  The single choke point for switching plugs (`Switching::Commander`): publishes the
  command and logs it to `switch_commands` only after the publish went out.

  By the mode of `switching`:

    * `:phoenix` — publishes over the command connection (`Ziwoas.Mqtt.publish/5`,
      which checks ownership itself) and writes the main database;
    * `:dry_run` — logs what it would publish and records the command in the shadow
      database, so a week of decisions compares with Rails' `switch_commands`;
    * `:rails` — raises `Ziwoas.Ownership.NotOwnerError` before anything is sent.
  """
  require Logger

  alias Ziwoas.{Mqtt, Ownership, Repo}
  alias Ziwoas.Plugs.Plug
  alias Ziwoas.Switching.Command

  @task :switching
  @actions [:on, :off]

  @spec switch(Plug.t(), :on | :off, :manual | :schedule, %Ziwoas.Config.Mqtt{}) ::
          {:ok, %Command{}} | {:error, String.t()}
  def switch(plug, action, source, mqtt) do
    unless action in @actions,
      do: raise(ArgumentError, "action must be one of #{inspect(@actions)}")

    with :ok <- switchable(plug),
         :ok <- publish(plug, action, mqtt) do
      command = %Command{plug_id: plug.id, action: to_string(action), source: to_string(source)}
      {:ok, Repo.write(@task, fn -> Repo.insert!(command) end)}
    end
  end

  defp switchable(%Plug{switchable: true}), do: :ok
  defp switchable(plug), do: {:error, "plug '#{plug.id}' is not switchable"}

  defp publish(%Plug{driver: :shelly} = plug, action, mqtt) do
    topic = "#{mqtt.topic_prefix}/#{plug.id}/command/switch:0"
    payload = to_string(action)

    if Ownership.mode(@task) == :dry_run do
      Logger.info("switching dry run: would publish #{topic} #{payload}")
      :ok
    else
      case Mqtt.publish(@task, Mqtt.command_client_id(), topic, payload) do
        :ok -> :ok
        {:error, reason} -> {:error, "MQTT publish for '#{plug.id}' failed: #{inspect(reason)}"}
      end
    end
  end

  defp publish(plug, _action, _mqtt),
    do: {:error, "no switch driver for '#{plug.driver}' (plug '#{plug.id}')"}
end
