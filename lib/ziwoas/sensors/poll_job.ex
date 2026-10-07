defmodule Ziwoas.Sensors.PollJob do
  @moduledoc """
  The `poll_sensors` job: one reading per configured SwitchBot sensor, all stamped
  with the same instant; a sensor that fails is logged and skipped. Then the TRMNL
  sensor widget, then the Sensoren and Wetter pages hear of it.

  The push's failure is logged and keeps neither the readings nor the page update
  back.
  """
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.{Clock, Live, Repo}
  alias Ziwoas.Sensors.{Reading, SwitchBotClient}
  alias Ziwoas.Trmnl.{Push, SensorPayload}

  @impl true
  def perform(context) do
    config = Ziwoas.Scheduler.Job.config(context)

    if is_nil(config.switchbot) or config.sensors == [] do
      Logger.info("sensors: not configured")
    else
      now = Clock.now()
      Enum.each(config.sensors, &poll(config.switchbot, &1, now))
      push(config)

      Live.broadcast("sensors", {:sensors_updated})
      Live.broadcast("weather", {:weather_updated})
    end

    :ok
  end

  defp poll(auth, sensor, now) do
    with {:ok, data} <- SwitchBotClient.device_status(auth, sensor.id),
         {:ok, _reading} <- Repo.insert(Reading.changeset(sensor.id, now, data)) do
      :ok
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning("SensorPoll[#{sensor.id}]: invalid reading #{inspect(changeset.errors)}")

      {:error, message} ->
        Logger.warning("SensorPoll[#{sensor.id}]: #{message}")
    end
  end

  defp push(config) do
    Push.run(:sensors, config.trmnl.sensors_webhook_url, fn ->
      SensorPayload.build(config, Clock.now())
    end)
  rescue
    error -> Logger.error("TRMNL sensor push: #{Exception.message(error)}")
  end
end
