defmodule Ziwoas.Trmnl.SensorPushJob do
  @moduledoc """
  Pushes the „Raumluft“ widget. With SwitchBot sensors to poll, the poll runs it right after
  polling, so the widget shows their new values; otherwise it runs on its own schedule.
  """
  @behaviour Ziwoas.Scheduler.Job

  alias Ziwoas.Clock
  alias Ziwoas.Trmnl.{Push, SensorPayload}

  @impl true
  def perform(opts) do
    config = Keyword.fetch!(opts, :config)

    Push.run(:sensors, config.trmnl.sensors_webhook_url, fn ->
      SensorPayload.build(config, Clock.now())
    end)
  end
end
