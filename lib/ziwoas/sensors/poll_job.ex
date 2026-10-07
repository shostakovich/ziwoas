defmodule Ziwoas.Sensors.PollJob do
  @moduledoc """
  Rails' `SensorPollJob` (`poll_sensors`) with the `TrmnlSensorPushJob` it
  enqueues: one reading per configured SwitchBot sensor, all stamped with the
  same instant; a sensor that fails is logged and skipped. Then the TRMNL
  sensor widget and, as owner, the Sensoren and Wetter pages.

  The push runs here, after the readings, instead of as a job of its own; its
  failure is logged and keeps neither the readings nor the page update back.
  """
  @behaviour Ziwoas.Scheduler.Job

  require Logger

  alias Ziwoas.{Clock, Live, RailsCast, Repo}
  alias Ziwoas.Sensors.{Reading, SwitchBotClient}
  alias Ziwoas.Trmnl.{Push, SensorPayload}

  @impl true
  def perform(%{task: task} = context) do
    config = Ziwoas.Scheduler.Job.config(context)

    if is_nil(config.switchbot) or config.sensors == [] do
      Logger.info("sensors: not configured")
    else
      now = Clock.now()

      Repo.write(task, fn ->
        Enum.each(config.sensors, &poll(config.switchbot, &1, now))
        push(task, config)
      end)

      Live.broadcast(task, "sensors", {:sensors_updated})
      Live.broadcast(task, "weather", {:weather_updated})
    end

    :ok
  end

  defp poll(auth, sensor, now) do
    case SwitchBotClient.device_status(auth, sensor.id) do
      {:ok, data} ->
        Repo.insert!(%Reading{
          device_id: sensor.id,
          taken_at: now,
          temperature: RailsCast.float(data.temperature),
          humidity: RailsCast.integer(data.humidity),
          co2: RailsCast.integer(data.co2),
          battery_pct: RailsCast.integer(data.battery_pct),
          firmware_version: RailsCast.string(data.firmware_version)
        })

      {:error, message} ->
        Logger.warning("SensorPoll[#{sensor.id}]: #{message}")
    end
  end

  defp push(task, config) do
    Push.run(task, :sensors, config.trmnl.sensors_webhook_url, fn ->
      SensorPayload.build(config, Clock.now())
    end)
  rescue
    error -> Logger.error("TRMNL sensor push: #{Exception.message(error)}")
  end
end
