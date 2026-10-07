defmodule Ziwoas.Sensors.PollJob do
  @moduledoc false
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.{Clock, Sensors}
  alias Ziwoas.Sensors.SwitchBotClient
  alias Ziwoas.Trmnl.{Push, SensorPayload}

  @impl true
  def perform(opts) do
    config = Keyword.fetch!(opts, :config)
    now = Clock.now()
    Enum.each(config.sensors, &poll(config.switchbot, &1, now))
    Sensors.notify_polled(now)

    Push.run(:sensors, config.trmnl.sensors_webhook_url, fn ->
      SensorPayload.build(config, Clock.now())
    end)
  end

  defp poll(auth, sensor, now) do
    with {:ok, data} <- SwitchBotClient.device_status(auth, sensor.id),
         {:ok, _reading} <- Sensors.create_reading(sensor.id, now, data) do
      :ok
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning("SensorPoll[#{sensor.id}]: invalid reading #{inspect(changeset.errors)}")

      {:error, %{__exception__: true} = exception} ->
        Logger.warning("SensorPoll[#{sensor.id}]: #{Exception.message(exception)}")

      {:error, reason} ->
        Logger.warning("SensorPoll[#{sensor.id}]: #{inspect(reason)}")
    end
  end
end
