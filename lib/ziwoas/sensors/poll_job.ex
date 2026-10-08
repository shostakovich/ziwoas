defmodule Ziwoas.Sensors.PollJob do
  @moduledoc false
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.{Clock, Sensors}
  alias Ziwoas.Config.Sensor
  alias Ziwoas.Sensors.SwitchBotClient
  alias Ziwoas.Trmnl.SensorPushJob

  @impl true
  def perform(opts) do
    config = Keyword.fetch!(opts, :config)
    now = Clock.now()

    for sensor <- config.sensors,
        Sensor.switchbot?(sensor),
        do: poll(config.switchbot, sensor, now)

    Sensors.notify_polled(now)
    SensorPushJob.perform(opts)
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
